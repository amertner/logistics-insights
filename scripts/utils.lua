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

return utils