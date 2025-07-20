local utils = {}

function utils.starts_with(str, prefix)
  return string.sub(str, 1, string.len(prefix)) == prefix
end

function utils.get_random(list)
  if list and #list ~= table_size(list) then
    assert(false, "Need to use table_size!")
  end
  if not list or #list == 0 then
    return nil
  end
  local index = math.random(1, #list)
  return list[index]
end

function utils.distance(pos1, pos2)
  local x1 = pos1.x or pos1[1]
  local y1 = pos1.y or pos1[2]
  local x2 = pos2.x or pos2[1]
  local y2 = pos2.y or pos2[2]
  return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end


return utils