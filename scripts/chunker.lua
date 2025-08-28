-- Process lists of entities in chunks to avoid performance issues

---@class Progress
---@field current number The current progress index
---@field total number The total number of items to process

---@class GatherOptions
---@field quality? boolean
---@field history? boolean
---@
---@class Chunker
---@field CHUNK_SIZE number The size of each chunk to process
---@field gather GatherOptions
---@field current_index number The current index in the processing list
---@field processing_list LuaEntity[]|nil The list of entities to process in chunks
---@field processing_count number The total number of entities to process
---@field partial_data table Accumulator for partial data during processing
---@field networkdata LINetworkData|nil The network data associated with this chunker
local chunker = {}
chunker.__index = chunker
script.register_metatable("logistics-insights-Chunker", chunker)

--- Create a new chunker instance for processing entities in chunks
--- @return Chunker The new chunker instance
function chunker.new()
  local self = setmetatable({}, chunker)
  self.CHUNK_SIZE = tonumber(settings.global["li-chunk-size-global"].value) or 207
  self.gather = {}
  if settings.global["li-gather-quality-data-global"].value then
    self.gather.quality = true
  end
  self.current_index = 1
  self.processing_list = nil
  self.processing_count = 0
  self.partial_data = {}
  self.networkdata = nil
  return self
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
  self.current_index = 1
  self.CHUNK_SIZE = tonumber(settings.global["li-chunk-size-global"].value) or 208
  self.gather = gather_options or {}
  if settings.global["li-gather-quality-data-global"].value then
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
  on_completion(self.partial_data, self.gather, self.networkdata)
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
function chunker:is_done()
  return self.processing_count == 0 or self.current_index > self.processing_count
end

--- Get the number of chunks remaining to be processed
--- @return number The number of chunks remaining
function chunker:get_chunks_remaining()
  if self:is_done() then
    return 0
  else
    return math.ceil((self.processing_count - self.current_index + 1) / self.CHUNK_SIZE)
  end
end

--- Get the current processing progress
--- @return Progress A table with current and total progress values
function chunker:get_progress()
  if not self.processing_list then
    return {
      current = 0,
      total = 0,
    }
  else
    return {
      current = self.current_index,
      total = self.processing_count,
    }
  end
end

--- Get the partial data accumulator
--- @return table The partial data being accumulated during processing
function chunker:get_partial_data()
  return self.partial_data
end

--- Process one chunk of entities from the current list
--- @param on_process_entity function(entity, partial_data, player_table)
--- @param on_completion function(partial_data, player_table)
function chunker:process_chunk(on_process_entity, on_completion)
  local processing_list = self.processing_list
  if self.processing_count == 0 or not processing_list then
    on_completion(self.partial_data, self.gather, self.networkdata)
    return
  end

  local list_size = self.processing_count
  local current_index = self.current_index
  local chunk_size = self.CHUNK_SIZE
  local end_index = math.min(current_index + chunk_size - 1, list_size)
  
  for i = current_index, end_index do
    local entity = processing_list[i]
    if entity.valid then
      on_process_entity(entity, self.partial_data, self.gather, self.networkdata)
    end
  end

  self.current_index = end_index + 1

  if end_index + 1 > list_size then
    on_completion(self.partial_data, self.gather, self.networkdata)
  end
end

return chunker