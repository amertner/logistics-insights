-- Process lists of entities in chunks to avoid performance issues

local player_data = require("scripts.player-data")

---@class Progress
---@field current number The current progress index
---@field total number The total number of items to process

---@class Chunker
---@field CHUNK_SIZE number The size of each chunk to process
---@field current_index number The current index in the processing list
---@field processing_list LuaEntity[]|nil The list of entities to process in chunks
---@field partial_data table Accumulator for partial data during processing
---@field player_table PlayerData|nil The player's data table containing settings
local chunker = {}
chunker.__index = chunker
script.register_metatable("logistics-insights-Chunker", chunker)

--- Create a new chunker instance for processing entities in chunks
--- @param player_table PlayerData|nil The player's data table containing settings
--- @return Chunker The new chunker instance
function chunker.new(player_table)
  local self = setmetatable({}, chunker)
  self.CHUNK_SIZE = player_table and player_table.settings.chunk_size or 207
  self.current_index = 1
  self.processing_list = nil
  self.partial_data = {}
  self.player_table = player_table
  return self
end

--- Initialize chunking with a list of entities to process
--- @param list table|nil The list of entities to process in chunks
--- @param player_table PlayerData|nil The player's data table containing settings
--- @param initial_data any|nil Initial data to pass to the initialization function
--- @param on_init function(partial_data, initial_data) 
function chunker:initialise_chunking(list, player_table, initial_data, on_init)
  self.processing_list = list
  self.current_index = 1
  self.player_table = player_table
  if self.player_table and self.player_table.settings.chunk_size then
    self.CHUNK_SIZE = self.player_table.settings.chunk_size
  end
  on_init(self.partial_data, initial_data)
end

--- Reset the chunker and complete current processing
--- @param on_init function(partial_data, initial_data) 
--- @param on_completion function(partial_data, player_table)
function chunker:reset(on_init, on_completion)
  -- Do whatever needs doing when the list is done
  on_completion(self.partial_data, self.player_table)
  -- Reset the counter and claim completion
  self:initialise_chunking(nil, self.player_table, nil, on_init)
end

--- Get the total number of chunks needed to process the current list
--- @return number The number of chunks
function chunker:num_chunks()
  if not self.processing_list or #self.processing_list == 0 then
    return 0
  else
    return math.ceil(#self.processing_list / self.CHUNK_SIZE)
  end
end

--- Check if all chunks have been processed
--- @return boolean True if processing is complete
function chunker:is_done()
  return not self.processing_list or #self.processing_list == 0 or self.current_index > #self.processing_list
end

--- Get the number of chunks remaining to be processed
--- @return number The number of chunks remaining
function chunker:get_chunks_remaining()
  if self:is_done() then
    return 0
  else
    return math.ceil((#self.processing_list - self.current_index + 1) / self.CHUNK_SIZE)
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
      total = #self.processing_list,
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
  if not processing_list or #processing_list == 0 then
    on_completion(self.partial_data, self.player_table)
    return
  end

  local list_size = #processing_list
  local current_index = self.current_index
  local chunk_size = self.CHUNK_SIZE
  local end_index = math.min(current_index + chunk_size - 1, list_size)
  
  for i = current_index, end_index do
    local entity = processing_list[i]
    if entity.valid then
      on_process_entity(entity, self.partial_data, self.player_table)
    end
  end

  self.current_index = end_index + 1

  if end_index + 1 > list_size then
    on_completion(self.partial_data, self.player_table)
  end
end

return chunker