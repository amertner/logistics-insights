-- Process lists of entities in chunks to avoid performance issues

chunker = {}
local player_data = require("scripts.player-data")

function chunker.new(call_on_init, call_on_processing, call_on_completion)
  local instance = {
    CHUNK_SIZE = 800,   -- May be changed by user setting
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

function chunker:initialise_chunking(list)
  self.processing_list = list
  self.player_table = player_data.get_singleplayer_table()
  self.on_init(self.partial_data)
end

function chunker:is_done()
  return not self.processing_list or #self.processing_list == 0 or self.current_index > #self.processing_list
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
    self.current_index = 1
    self.processing_list = nil
    self.on_completion(self.partial_data)
  end
end

return chunker