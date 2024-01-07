local M = {}

local default_config = {
  date_formatter = function(ts, tz_offset)
    return os.date('%Y-%m-%d %H:%M:%S', ts) .. ' ' .. tz_offset
  end,
  long_hash = false,
}

function M.setup(opts)
  local new_conf = vim.tbl_deep_extend('keep', opts or {}, default_config)
  for k, v in pairs(new_conf) do
    M[k] = v
  end
end

return M
