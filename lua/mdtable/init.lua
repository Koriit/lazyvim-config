-- mdtable: inspect a wide markdown-table row in a wrapping float.
--
-- Public API:
--   require("mdtable").inspect()   -- open inspector for table at cursor
--
-- Inside the float:
--   <C-n> / <Tab>      next data row
--   <C-p> / <S-Tab>    previous data row
--   gg / G             first / last data row
--   q  / <Esc>         close
--
-- j/k are intentionally left alone so long cells can still be scrolled.

local M = {}

local function is_table_line(line)
  return line:match("^%s*|") ~= nil
end

local function is_separator_line(line)
  if not is_table_line(line) then
    return false
  end
  local stripped = line:gsub("|", ""):gsub("%s", "")
  return stripped ~= "" and stripped:match("^[-:]+$") ~= nil
end

-- Split a markdown table row into trimmed cells, honouring escaped pipes (\|).
local function split_cells(line)
  line = line:match("^%s*(.-)%s*$") or ""
  if line:sub(1, 1) == "|" then
    line = line:sub(2)
  end
  if line:sub(-1) == "|" then
    line = line:sub(1, -2)
  end

  local cells, current = {}, {}
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == "\\" and line:sub(i + 1, i + 1) == "|" then
      current[#current + 1] = "|"
      i = i + 2
    elseif c == "|" then
      cells[#cells + 1] = vim.trim(table.concat(current))
      current = {}
      i = i + 1
    else
      current[#current + 1] = c
      i = i + 1
    end
  end
  cells[#cells + 1] = vim.trim(table.concat(current))
  return cells
end

-- Locate the table containing `lnum`. Returns a table with header / first_data /
-- last_data line numbers (1-indexed), or nil if the cursor isn't in a table.
local function find_table(bufnr, lnum)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, total, false)

  if not is_table_line(lines[lnum] or "") then
    return nil
  end

  local first, last = lnum, lnum
  while first > 1 and is_table_line(lines[first - 1] or "") do
    first = first - 1
  end
  while last < total and is_table_line(lines[last + 1] or "") do
    last = last + 1
  end

  local sep
  for ln = first, last do
    if is_separator_line(lines[ln]) then
      sep = ln
      break
    end
  end
  if not sep or sep == first then
    return nil
  end

  return {
    header = sep - 1,
    first_data = sep + 1,
    last_data = last,
    lines = lines,
  }
end

local function format_row(headers, cells)
  local out = {}
  local n = math.max(#headers, #cells)
  for i = 1, n do
    local h = headers[i] ~= nil and headers[i] ~= "" and headers[i] or ("Column " .. i)
    local c = cells[i] or ""
    -- Common in-cell line-break conventions in wide markdown tables.
    c = c:gsub("<br%s*/?>", "\n")
    if #out > 0 then
      out[#out + 1] = ""
    end
    out[#out + 1] = "## " .. h
    out[#out + 1] = ""
    for _, l in ipairs(vim.split(c, "\n", { plain = true })) do
      out[#out + 1] = l
    end
  end
  return out
end

local function open_float()
  local width = math.max(40, math.floor(vim.o.columns * 0.6))
  local height = math.max(10, math.floor(vim.o.lines * 0.6))
  width = math.min(width, vim.o.columns - 4)
  height = math.min(height, vim.o.lines - 4)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " markdown table ",
    title_pos = "center",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false

  return buf, win
end

local function render(state)
  if not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local cells = state.rows[state.current]
  local lines = format_row(state.headers, cells)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_win_set_cursor(state.win, { 1, 0 })

  pcall(vim.api.nvim_win_set_config, state.win, {
    title = string.format(" markdown table — row %d/%d ", state.current, #state.rows),
    title_pos = "center",
  })

  if state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
    local target = state.first_data + state.current - 1
    pcall(vim.api.nvim_win_set_cursor, state.source_win, { target, 0 })
  end
end

local function step(state, delta)
  local next_idx = math.max(1, math.min(#state.rows, state.current + delta))
  if next_idx ~= state.current then
    state.current = next_idx
    render(state)
  end
end

local function jump(state, idx)
  idx = math.max(1, math.min(#state.rows, idx))
  if idx ~= state.current then
    state.current = idx
    render(state)
  end
end

function M.inspect()
  local source_win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(source_win)
  local lnum = vim.api.nvim_win_get_cursor(source_win)[1]

  local info = find_table(bufnr, lnum)
  if not info then
    vim.notify("No markdown table at cursor", vim.log.levels.INFO, { title = "mdtable" })
    return
  end

  local headers = split_cells(info.lines[info.header])
  local rows = {}
  for ln = info.first_data, info.last_data do
    rows[#rows + 1] = split_cells(info.lines[ln])
  end
  if #rows == 0 then
    vim.notify("Table has no data rows", vim.log.levels.INFO, { title = "mdtable" })
    return
  end

  local current = math.max(1, math.min(#rows, lnum - info.first_data + 1))

  local buf, win = open_float()
  local state = {
    buf = buf,
    win = win,
    headers = headers,
    rows = rows,
    current = current,
    first_data = info.first_data,
    source_win = source_win,
  }
  render(state)

  local function close()
    if vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
  end

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, {
      buffer = state.buf,
      nowait = true,
      silent = true,
      desc = desc,
    })
  end

  map("<C-n>", function()
    step(state, 1)
  end, "mdtable: next row")
  map("<Tab>", function()
    step(state, 1)
  end, "mdtable: next row")
  map("<C-p>", function()
    step(state, -1)
  end, "mdtable: prev row")
  map("<S-Tab>", function()
    step(state, -1)
  end, "mdtable: prev row")
  map("gg", function()
    jump(state, 1)
  end, "mdtable: first row")
  map("G", function()
    jump(state, #state.rows)
  end, "mdtable: last row")
  map("q", close, "mdtable: close")
  map("<Esc>", close, "mdtable: close")
end

return M
