-- Process lists of entities in chunks to avoid performance issues

local global_data = require("scripts.global-data")
local debugger = require("scripts.debugger")
local PERF_LOGGING = debugger.PROFILING

-- Fetcher functions stored outside storage to avoid serialization issues.
-- Keyed by chunker instance; entries are transient and lost on save/load.
local pending_fetchers = {}

---@class Progress
---@field current number The current progress index
---@field total number The total number of items to process

---@class GatherOptions
---@field quality? boolean
---@field history? boolean

-- State machine
--
-- States:
--   "idle"       — No work. Waiting for initialise_chunking() to be called.
--   "fetching"   — Initialised with a deferred fetcher function. List not yet loaded.
--   "processing" — Entity list is loaded and being processed in chunks.
--   "finalising" — All entities processed (or list was empty). Awaiting finalise_run().
--
-- Transitions:
--
--   initialise_chunking(fetcher)
--     any ──► "fetching"              Fetcher stored; list will be loaded on first process_chunk.
--
--   initialise_chunking(list)
--     any ──► "processing"            If list has entities to process.
--     any ──► "finalising"            If list is nil/empty (nothing to process).
--
--   process_chunk()
--     "fetching" ──► "processing"     Fetcher resolved, list loaded. No entities processed this tick.
--     "fetching" ──► "finalising"     Fetcher resolved but list is empty (or fetcher lost after save/load).
--     "processing"   ──► "processing" Processed one chunk; more entities remain.
--     "processing"   ──► "finalising" Processed last chunk; all entities consumed.
--
--   finalise_run()
--     "finalising" ──► "idle"         Completion callback invoked. Chunker ready for reuse.
--
--   reset()
--     any ──► "idle" ──► (initialise_chunking with nil) ──► "finalising"
--                         Completes current run, then re-initialises with empty list.

---@class Chunker
---@field CHUNK_SIZE number The size of each chunk to process
---@field divisor number|nil The divisor used to adjust chunk size for heavy tasks
---@field gather GatherOptions
---@field current_index number The current index in the processing list
---@field processing_list LuaEntity[]|nil The list of entities to process in chunks
---@field processing_count number The total number of entities to process
---@field partial_data table Accumulator for partial data during processing
---@field network_id number|nil The network data associated with this chunker
---@field state string The current state of the chunker ("idle", "fetching", "processing", "finalising")
local chunker = {}
chunker.__index = chunker
script.register_metatable("logistics-insights-Chunker", chunker)

--- Create a new chunker instance for processing entities in chunks
--- @return Chunker The new chunker instance
function chunker.new()
  local self = setmetatable({}, chunker)
  self.divisor = 1
  self:set_chunk_size()
  self.gather = {}
  self.gather.quality = global_data.gather_quality_data()
  self.current_index = 1
  self.processing_list = nil
  self.processing_count = 0
  self.partial_data = {}
  self.network_id = nil
  self.state = "idle"
  self._progress = { current = 0, total = 0 }
  return self
end

function chunker:set_chunk_size()
  self.divisor = self.divisor or 1
  local base_chunk_size = global_data.chunk_size()
  self.CHUNK_SIZE = math.max(1, math.floor(base_chunk_size / self.divisor))
end

--- Initialize chunking with a list of entities to process
--- @param network_id number The network data associated with this chunker
--- @param list_or_fetcher table|function|nil The list of entities, or a function that returns the list (for deferred loading)
--- @param initial_data any|nil Initial data to pass to the initialization function
--- @param gather_options GatherOptions Options for what to gather during processing
--- @param on_init function(partial_data, initial_data)
--- @param divisor number|nil Optional divisor to adjust chunk size (default: keep current)
--- @param name string|nil Optional name for perf logging to identify this chunker
function chunker:initialise_chunking(network_id, list_or_fetcher, initial_data, gather_options, on_init, divisor, name)
  self.current_index = 1
  if divisor then self.divisor = math.max(divisor, 1) end
  if name then self._name = name end
  self:set_chunk_size() -- Update in case the setting changed
  self.gather = gather_options or {}
  self.gather.quality = global_data.gather_quality_data()
  self.network_id = network_id

  if type(list_or_fetcher) == "function" then
    pending_fetchers[self] = list_or_fetcher
    self.processing_list = nil
    self.processing_count = 0
    self.state = "fetching"
  else
    pending_fetchers[self] = nil
    self.processing_list = list_or_fetcher
    self.processing_count = list_or_fetcher and #list_or_fetcher or 0
    if self.processing_count > 0 then
      self.state = "processing"
    else
      self.state = "finalising"
    end
  end

  on_init(self.partial_data, initial_data)
end

--- Reset the chunker and complete current processing
--- @param network_id number The network data associated with this chunker
--- @param on_init function(partial_data, initial_data)
--- @param on_completion function(partial_data, player_table, network_id)
function chunker:reset(network_id, on_init, on_completion)
  -- Do whatever needs doing when the list is done
  if self.state ~= "idle" then
    self.state = "idle"
    on_completion(self.partial_data, self.gather, self.network_id)
    self.processing_list = nil -- Save memory by clearing this
  end
  -- Reset the counter and claim completion
  self:initialise_chunking(0, nil, network_id, self.gather, on_init)
end

--- Get the total number of chunks needed to process the current list
--- @return number The number of chunks
function chunker:num_chunks()
  if self.processing_count == 0 then
    return 0
  else
    return math.ceil(self.processing_count / self.CHUNK_SIZE)
  end
end

--- Check if there is or has been something to process
--- @return boolean True if processing is complete
function chunker:is_processing()
  return self.processing_count > 0
end

--- Check if the chunker needs new data to work on
--- @return boolean True if the chunker is idle and ready for new data
function chunker:needs_data()
  return self.state == "idle"
end

--- Check if the run is done and needs finalisation
--- @return boolean True if all entities have been processed
function chunker:needs_finalisation()
  return self.state == "finalising"
end

--- Check if the run needs more processing (including pending fetcher resolution)
--- @return boolean True if processing is needed
function chunker:needs_processing()
  return self.state == "fetching" or (self.state == "processing" and self.current_index <= self.processing_count)
end

--- Check if the chunker has completed its work
--- @return boolean True if the chunker is idle
function chunker:is_done_processing()
  return self.state == "idle"
end

--- Get the current processing progress
--- @return Progress A table with current and total progress values
function chunker:get_progress()
  local prog = self._progress or { current = 0, total = 0 }
  self._progress = prog
  if not self.processing_list then
    prog.current = 0
    prog.total = 0
  else
    prog.current = self.current_index
    prog.total = self.processing_count
  end
  return prog
end

--- Get the partial data accumulator
--- @return table The partial data being accumulated during processing
function chunker:get_partial_data()
  return self.partial_data
end

--- Finalise the run, if needed, then mark as idle
--- @param on_completion function(partial_data, player_table)
function chunker:finalise_run(on_completion)
  if self.state == "finalising" then
    on_completion(self.partial_data, self.gather, self.network_id)
    self.state = "idle"
  end
end

--- Process one chunk of entities from the current list
--- @param on_process_entity function(entity, partial_data, gather_options, network_id)
function chunker:process_chunk(on_process_entity)
  -- Resolve pending fetcher on its own tick
  if self.state == "fetching" then
    local fetcher = pending_fetchers[self]
    if fetcher then
      local list = fetcher()
      self.processing_list = list
      self.processing_count = list and #list or 0
      pending_fetchers[self] = nil
    end
    if self.processing_count > 0 then
      self.state = "processing"
    else
      self.state = "finalising" -- Empty or missing list, skip straight to done
    end
    return -- Defer actual processing to next call
  end

  if self.state ~= "processing" then
    return -- Nothing to do
  end

  local processing_list = self.processing_list or {}
  local list_size = self.processing_count
  local current_index = self.current_index
  local start_index = current_index
  local chunk_size = self.CHUNK_SIZE

  local consumed = 0
  while (consumed < chunk_size) and (current_index <= list_size) do
    local entity = processing_list[current_index]
    if entity and entity.valid then
      local cost = on_process_entity(entity, self.partial_data, self.gather, self.network_id)
      consumed = consumed + cost
    end
    current_index = current_index + 1
  end

  if PERF_LOGGING then
    log("[perf] chunk " .. (self._name or "?") .. " n=" .. (current_index - start_index) .. " cost=" .. consumed .. "/" .. chunk_size)
  end

  self.current_index = current_index

  -- Transition to done if all entities have been processed
  if current_index > list_size then
    self.state = "finalising"
  end
end

return chunker
