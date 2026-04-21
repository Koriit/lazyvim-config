local M = {}

local function get_visual_selection()
  local _, start_row, start_col, _ = unpack(vim.fn.getpos("'<"))
  local _, end_row, end_col, _ = unpack(vim.fn.getpos("'>"))

  local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)

  if #lines == 0 then
    return ""
  end

  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    lines[1] = string.sub(lines[1], start_col)
    if end_col > 0 then
      lines[#lines] = string.sub(lines[#lines], 1, end_col)
    end
  end

  return table.concat(lines, "\n")
end

local function shell_escape(str)
  return "'" .. str:gsub("'", "'\"'\"'") .. "'"
end

function M.kai_enhance()
  vim.cmd("highlight KaiPrompt guifg=#e0e0e0 guibg=#1a1a2e")

  vim.cmd("echohl KaiPrompt")
  local prompt = vim.fn.input("🤖 Kai: ")
  vim.cmd("echohl None")

  if prompt == "" then
    print("No instruction provided.")
    return
  end

  local mode = vim.fn.mode()
  local is_visual = mode == "v" or mode == "V" or mode == ""

  local selection = ""
  if is_visual then
    selection = get_visual_selection()
  end

  local filepath = vim.fn.expand("%:p")

  local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

  local buffer_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

  local context_file = os.tmpname()
  local f = io.open(context_file, "w")
  f:write("CURRENT FILE: " .. filepath .. "\n\n")

  f:write("FULL BUFFER CONTENT:\n" .. buffer_content .. "\n\n")

  f:write("CURSOR POSITION: Line " .. cursor_row .. ", Column " .. cursor_col .. "\n\n")

  if is_visual then
    local _, start_row, start_col, _ = unpack(vim.fn.getpos("'<"))
    local _, end_row, end_col, _ = unpack(vim.fn.getpos("'>"))

    f:write("SELECTED TEXT (Lines " .. start_row .. "-" .. end_row .. "):\n" .. selection .. "\n\n")
    f:write(
      "MODE: User has selected specific text. Focus on this selection within the context of the entire buffer.\n\n"
    )
  else
    f:write(
      "MODE: No selection. User's cursor is at line "
        .. cursor_row
        .. ". Make targeted changes based on cursor location unless instructed otherwise.\n\n"
    )
  end

  f:write("INSTRUCTION: " .. prompt .. "\n")
  f:close()

  local script = vim.fn.stdpath("config") .. "/lua/kai/scripts/kai.sh"
  local cmd = string.format("%s %s %s", shell_escape(script), shell_escape(context_file), shell_escape(prompt))

  print("🤖 Processing with Kai...")

  local output = vim.fn.system(cmd)

  os.remove(context_file)

  local lines = vim.split(output, "\n", { plain = true })
  local action = lines[1]
  local content_lines = {}
  for i = 2, #lines do
    if lines[i] ~= "" or i < #lines then
      table.insert(content_lines, lines[i])
    end
  end
  local content = table.concat(content_lines, "\n")

  content = content:gsub("\n$", "")

  if action == "[ACTION:DISPLAY]" then
    local display_buf = vim.api.nvim_create_buf(false, true)
    local display_lines = vim.split(content, "\n", { plain = true })

    local width = math.min(80, vim.o.columns - 10)
    local height = math.min(#display_lines + 2, vim.o.lines - 10)

    vim.api.nvim_buf_set_lines(display_buf, 0, -1, false, display_lines)

    local display_win = vim.api.nvim_open_win(display_buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = "rounded",
      title = " Kai Analysis ",
      title_pos = "center",
    })

    local close_keys = { "<Esc>", "q", "<CR>" }
    for _, key in ipairs(close_keys) do
      vim.api.nvim_buf_set_keymap(
        display_buf,
        "n",
        key,
        ":lua vim.api.nvim_win_close(" .. display_win .. ", true)<CR>",
        { noremap = true, silent = true }
      )
    end

    print("Kai analysis complete! Press <Esc>, q, or <Enter> to close.")
    return
  end

  if is_visual then
    if action == "[ACTION:REPLACE]" then
      local save_reg = vim.fn.getreg('"')
      local save_regtype = vim.fn.getregtype('"')

      vim.fn.setreg('"', content, mode == "V" and "V" or "v")
      vim.cmd('normal! gv"_d')
      vim.cmd("normal! P")

      vim.fn.setreg('"', save_reg, save_regtype)
    elseif action == "[ACTION:INSERT_AFTER]" then
      vim.cmd("normal! gv")
      vim.cmd("normal! o")
      vim.cmd("normal! ")

      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local content_lines_new = vim.split(content, "\n", { plain = true })

      vim.api.nvim_buf_set_lines(0, row, row, false, { "" })
      vim.api.nvim_buf_set_lines(0, row + 1, row + 1, false, content_lines_new)
    end
  else
    local content_lines_new = vim.split(content, "\n", { plain = true })
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))

    vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, content_lines_new)
  end

  print("Kai enhancement complete!")
end

return M
