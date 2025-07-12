-- Process lists of entities in chunks to avoid performance issues

chunker = {}
local player_data = require("scripts.player-data")

function chunker.new(call_on_init, call_on_processing, call_on_completion)
  local instance = {
    CHUNK_SIZE = 200,
    current_index = 1,
    processing_list = nil,
    partial_data = {},
    on_init = call_on_init or function(partial_data) end,
    on_process_entity = call_on_processing or function(entity, partial_data, player_table) end,
    on_completion = call_on_completion or function(data) end,
    player_table = nil,
  }
  setmetatable(instance, { __index = chunker })
  return instance
end

function chunker:initialise_chunking(list, player_table)
  self.processing_list = list
  self.current_index = 1
  self.player_table = player_table
  if self.player_table.settings.chunk_size then
    self.CHUNK_SIZE = self.player_table.settings.chunk_size
  end
  self.on_init(self.partial_data)
end

function chunker:reset()
  -- Reset the counter and claim completion
  self:initialise_chunking(nil, self.player_table or player_data.get_singleplayer_table())
  self.on_completion(self.partial_data)
end

function chunker:num_chunks()
  if not self.processing_list or #self.processing_list == 0 then
    return 0
  else
    return math.ceil(#self.processing_list / self.CHUNK_SIZE)
  end
end

function chunker:is_done()
  return not self.processing_list or #self.processing_list == 0 or self.current_index > #self.processing_list
end

function chunker:get_chunks_remaining()
  if self:is_done() then
    return 0
  else
    return math.ceil((#self.processing_list - self.current_index + 1) / self.CHUNK_SIZE)
  end
end

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

function chunker:process_chunk()
  if not self.processing_list or #self.processing_list == 0 then
    return
  end

  local end_index = math.min(self.current_index + self.CHUNK_SIZE - 1, #self.processing_list)
  for i = self.current_index, end_index do
    local entity = self.processing_list[i]
    if entity.valid then
      self.on_process_entity(entity, self.partial_data, self.player_table)
    end
  end

  self.current_index = end_index + 1

  if self.current_index > #self.processing_list then
    self.on_completion(self.partial_data)
  end
end

return chunker