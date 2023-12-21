local stringx = require 'gitblame.stringx'

local M = {}

local namespace = 'GitBlame'

local function line_porcelain_data(file)
  local result = vim.system({ 'git', 'blame', '--line-porcelain', file }, { text = true }):wait()
  if result.code ~= 0 then
    error('git blame failed with non-zero exit code ' .. result.code, 2)
    return
  end
  return result.stdout
end

local function parse_line_porcelain_data(data)
  local bls = {}

  local is_header_line = true
  local curr_bl = {}
  local max_author_width = 0 -- Used for calculating right padding of author names when displayed.
  for _, line in ipairs(stringx.split(data, '\n')) do
    -- End of a blame line data.
    if stringx.starts_with(line, '\t') then
      local _, _, text = stringx.lpartition(line, '\t')
      curr_bl.text = text

      bls[curr_bl.linenr_final_file] = curr_bl
      is_header_line = true
      goto continue
    end

    -- Start of blame line data.
    if is_header_line then
      local parts = stringx.split(line, ' ')
      curr_bl = {
        hash = parts[1],
        linenr_original_file = tonumber(parts[2]),
        linenr_final_file = tonumber(parts[3]),
      }
      is_header_line = false
      goto continue
    end

    local key, _, value = stringx.lpartition(line, ' ')
    value = stringx.trim_whitespace(value)
    if key == 'author' then
      curr_bl.author = value
      local author_width = vim.fn.strdisplaywidth(value)
      if author_width > max_author_width then
        max_author_width = author_width
      end
    elseif key == 'author-mail' then
      curr_bl.author_mail = value
    elseif key == 'author-time' then
      curr_bl.author_time = value
    elseif key == 'author-tz' then
      curr_bl.author_tz = value
    elseif key == 'committer' then
      curr_bl.committer = value
    elseif key == 'committer-mail' then
      curr_bl.committer_mail = value
    elseif key == 'committer-time' then
      curr_bl.committer_time = value
    elseif key == 'committer-tz' then
      curr_bl.committer_tz = value
    elseif key == 'summary' then
      curr_bl.summary = value
    elseif key == 'previous' then
      local parts = stringx.split(value, ' ')
      curr_bl.previous_hash = parts[1]
      curr_bl.previous_filename = parts[2]
    elseif key == 'filename' then
      curr_bl.filename = value
    end

    ::continue::
  end

  return {
    blame_lines = bls,
    meta = {
      max_author_width = max_author_width,
    },
  }
end

local function git_blame_buffer()
  local config = require 'gitblame.config'

  local ns_id = vim.api.nvim_create_namespace(namespace)

  local file = tostring(vim.fn.expand '%:p')
  local data = line_porcelain_data(file)
  local parsed_data = parse_line_porcelain_data(data)

  local blame_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(blame_bufnr, 'gitblame://' .. file)

  -- Write lines with highlight groups to buffer and calculate the width of the
  -- window we need to display the blame buffer based on the longest line.
  local blame_win_width = 0
  for _, bl in ipairs(parsed_data.blame_lines) do
    local linenr = bl.linenr_final_file

    local hash = bl.hash
    if not config.long_hash then
      hash = string.sub(bl.hash, 1, 8)
    end
    local author = bl.author
    if parsed_data.meta.max_author_width > vim.fn.strdisplaywidth(author) then
      -- Pad the author name with spaces to align the author time.
      author = author
        .. string.rep(' ', parsed_data.meta.max_author_width - vim.fn.strdisplaywidth(author))
    end
    local author_time = config.date_formatter(bl.author_time, bl.author_tz)
    local line = hash .. ' (' .. author .. ' ' .. author_time .. ')'

    vim.api.nvim_buf_set_lines(blame_bufnr, linenr - 1, linenr, false, { line })

    local add_highlight = function(hl_group, target)
      local start_col, end_col =
        string.find(line, stringx.escape_pattern(stringx.trim_whitespace(target)))
      vim.api.nvim_buf_add_highlight(
        blame_bufnr,
        ns_id,
        hl_group,
        linenr - 1,
        start_col - 1,
        end_col or -1
      )
    end
    add_highlight('GitBlameHash', hash)
    add_highlight('GitBlameAuthor', author)
    add_highlight('GitBlameAuthorTime', author_time)

    local line_width = vim.fn.strdisplaywidth(line)
    if line_width > blame_win_width then
      blame_win_width = line_width
    end
  end

  -- Account for the line number column.
  blame_win_width = blame_win_width + 1

  -- Configure the blame buffer. We can set it to be unmodifiable and readonly
  -- since we already populated it.
  local blame_buf_opts = {
    filetype = 'gitblame',
    modifiable = false,
    readonly = true,
    bufhidden = 'wipe',
    buftype = 'nofile',
    buflisted = false,
  }
  for k, v in pairs(blame_buf_opts) do
    vim.api.nvim_set_option_value(k, v, { buf = blame_bufnr })
  end

  -- Configure current window before we create a new one for the blame buffer.
  local main_win = vim.api.nvim_get_current_win()
  local main_win_opts = {
    foldenable = false,
    wrap = false,
    scrollbind = true,
    cursorbind = true,
  }
  for k, v in pairs(main_win_opts) do
    vim.api.nvim_set_option_value(k, v, { win = main_win })
  end

  -- Get the current line number and the line number at the top of the screen. We need this to
  -- calculate the offset of the blame window.
  local scrolloff = vim.api.nvim_get_option_value('scrolloff', {})
  local top = vim.fn.line 'w0' + scrolloff
  local current = vim.fn.line '.'

  -- Spawn a new window for the blame buffer in a vertical split.
  vim.cmd.split { mods = { vertical = true, keepalt = true } }
  local blame_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(blame_win, blame_bufnr)

  -- Sync the scroll of the blame window with the current window.
  vim.cmd("execute '" .. top .. "'")
  vim.cmd 'normal! zt'
  vim.cmd("execute '" .. current .. "'")

  -- Configure the blame window.
  local blame_win_opts = {
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    foldcolumn = '0',
    foldenable = false,
    wrap = false,
    winfixwidth = true,
    scrollbind = true,
    cursorbind = true,
  }
  for k, v in pairs(blame_win_opts) do
    vim.api.nvim_set_option_value(k, v, { win = blame_win })
  end
  vim.api.nvim_win_set_width(blame_win, blame_win_width)

  vim.cmd 'redraw'
  vim.cmd 'syncbind'
end

local function init_highlights()
  vim.cmd [[
    hi default link GitBlameHash DiagnosticError
    hi default link GitBlameAuthor DiagnosticOk
    hi default link GitBlameAuthorTime DiagnosticWarn
  ]]
end

function M.setup(opts)
  local config = require 'gitblame.config'
  config.setup(opts)
  vim.api.nvim_create_user_command(
    'GitBlameBuffer',
    git_blame_buffer,
    { desc = 'Open Git blame buffer for current file', nargs = '*' }
  )
  init_highlights()
end

function M.open_buffer()
  git_blame_buffer()
end

return M
