local M = {}

function M.lfind(s, sub, first, last)
  local i1, i2 = string.find(s, sub, first, true)
  if i1 and (not last or i2 <= last) then
    return i1
  else
    return nil
  end
end

local function partition(p, delim, fn)
  local i1, i2 = fn(p, delim)
  if not i1 or i1 == -1 then
    return p, '', ''
  else
    if not i2 then
      i2 = i1
    end
    return string.sub(p, 1, i1 - 1), string.sub(p, i1, i2), string.sub(p, i2 + 1)
  end
end

function M.lpartition(s, ch)
  return partition(s, ch, M.lfind)
end

function M.split(s, del)
  local result = {}
  local from = 1
  local delim_from, delim_to = string.find(s, del, from)
  while delim_from do
    table.insert(result, string.sub(s, from, delim_from - 1))
    from = delim_to + 1
    delim_from, delim_to = string.find(s, del, from)
  end
  table.insert(result, string.sub(s, from))
  return result
end

function M.starts_with(s, start)
  return s:sub(1, #start) == start
end

function M.trim_whitespace(s)
  return s:match('^%s*(.*)'):match '(.-)%s*$'
end

function M.escape_pattern(p)
  return (p:gsub('%W', '%%%1'))
end

return M
