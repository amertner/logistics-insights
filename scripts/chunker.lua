-- Process lists of entities in chunks to avoid performance issues

local global_data = require("scripts.global-data")

---@class Progress
---@field current number The current progress index
---@field total number The total number of items to process

---@class GatherOptions
---@field quality? boolean
---@field history? boolean

---@class Chunker
---@field CHUNK_SIZE number The size of each chunk to process
---@field divisor number|nil The divisor used to adjust chunk size for heavy tasks
---@field gather GatherOptions
---@field current_index number The current index in the processing list
---@field processing_list LuaEntity[]|nil The list of entities to process in chunks
---@field processing_count number The total number of entities to process
---@field partial_data table Accumulator for partial data during processing
---@field networkdata LINetworkData|nil The network data associated with this chunker
---@field is_finalised boolean Whether the chunker has completed processing
local chunker = {}
chunker.__index = chunker
script.register_metatable("logistics-insights-Chunker", chunker)

--- Create a new chunker instance for processing entities in chunks
--- @param divisor number|nil Optional divisor to adjust chunk size for heavy tasks
--- @return Chunker The new chunker instance
function chunker.new(divisor)
  local self = setmetatable({}, chunker)
  self.divisor = math.max(divisor or 1, 1)
  self:set_chunk_size()
  self.gather = {}
  if global_data.gather_quality_data() then
    self.gather.quality = true
  end
  self.current_index = 1
  self.processing_list = nil
  self.processing_count = 0
  self.partial_data = {}
  self.networkdata = nil
  self.is_finalised = true
  self._progress = { current = 0, total = 0 }
  return self
end

function chunker:set_chunk_size()
  self.divisor = self.divisor or 1
  local base_chunk_size = global_data.chunk_size()
  self.CHUNK_SIZE = math.max(1, math.floor(base_chunk_size / self.divisor))
end

--- Initialize chunking with a list of entities to process
--- @param networkdata LINetworkData|nil The network data associated with this chunker
--- @param list table|nil The list of entities to process in chunks
--- @param initial_data any|nil Initial data to pass to the initialization function
--- @param gather_options GatherOptions Options for what to gather during processing
--- @param on_init function(partial_data, initial_data) 
function chunker:initialise_chunking(networkdata, list, initial_data, gather_options, on_init)
  self.processing_list = list
  self.processing_count = list and #list or 0 -- Calculate once to avoid recounting
  self.is_finalised = false
  self.current_index = 1
  self:set_chunk_size() -- Update in case the setting changed since new()
  self.gather = gather_options or {}
  if global_data.gather_quality_data() then
    self.gather.quality = true
  end
  self.networkdata = networkdata
  on_init(self.partial_data, initial_data)
end

--- Reset the chunker and complete current processing
--- @param networkdata LINetworkData The network data associated with this chunker
--- @param on_init function(partial_data, initial_data) 
--- @param on_completion function(partial_data, player_table)
function chunker:reset(networkdata, on_init, on_completion)
  -- Do whatever needs doing when the list is done
  if not self.is_finalised then
    self.is_finalised = true
    on_completion(self.partial_data, self.gather, self.networkdata)
  end
  -- Reset the counter and claim completion
  self:initialise_chunking(nil, nil, networkdata, self.gather, on_init)
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

--- Check if all chunks have been processed
--- @return boolean True if processing is complete
function chunker:needs_data()
  return self.is_finalised -- If data has been finalised, then we need new data
end

--- Check if the run is done and needs finalisation
--- @return boolean True if processing is complete
function chunker:needs_finalisation()
  return not self.is_finalised and self.current_index > self.processing_count
end

--- Check if the run needs more processing
--- @return boolean True if processing is needed
function chunker:needs_processing()
  return not self.is_finalised and self.current_index <= self.processing_count
end

--- Check if the chunker has been finalised
--- @return boolean True if the chunker has been finalised
function chunker:is_done_processing()
  return self.is_finalised
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

--- Finalise the run, if needed, then mark as done
--- @param on_completion function(partial_data, player_table)
function chunker:finalise_run(on_completion)
  if not self.is_finalised then
    self.is_finalised = true
    on_completion(self.partial_data, self.gather, self.networkdata)
  end
end

--- Process one chunk of entities from the current list
--- @param on_process_entity function(entity, partial_data, gather_options, networkdata)
function chunker:process_chunk(on_process_entity)
  if self.is_finalised then
    return -- Nothing to do
  end

  local processing_list = self.processing_list or {}
  local list_size = self.processing_count
  local current_index = self.current_index
  local chunk_size = self.CHUNK_SIZE
 
  local consumed = 0
  while (consumed < chunk_size) and (current_index <= list_size) do
    local entity = processing_list[current_index]
    if entity.valid then
      local cost = on_process_entity(entity, self.partial_data, self.gather, self.networkdata)
      consumed = consumed + cost
    end
    current_index = current_index + 1
  end

  self.current_index = current_index
end

return chunker