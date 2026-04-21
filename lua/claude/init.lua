-- claude: inline AI assistant for Neovim, powered by the Claude CLI.
--
-- Sends the current buffer (plus any visual selection) and a user-supplied
-- instruction to an external shell script, which returns an action marker
-- followed by content. Supported actions:
--   [ACTION:REPLACE]       replace the visual selection
--   [ACTION:INSERT_AFTER]  insert after the visual selection
--   [ACTION:INSERT_BEFORE] insert before the cursor / selection
--   [ACTION:DISPLAY]       show the response in a floating markdown window
--
-- Entry point: require("claude").claude_enhance({ is_visual = true|false })
-- The backing script lives at lua/claude/scripts/claude.sh.

local M = {}

local NOTIF_ID = "claude"

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

function M.claude_enhance(opts)
  opts = opts or {}
  local is_visual = opts.is_visual == true

  local selection = ""
  local visual_mode = ""
  local sel_start_row, sel_start_col, sel_end_row, sel_end_col = 0, 0, 0, 0

  if is_visual then
    selection = get_visual_selection()
    visual_mode = vim.fn.visualmode()
    _, sel_start_row, sel_start_col, _ = unpack(vim.fn.getpos("'<"))
    _, sel_end_row, sel_end_col, _ = unpack(vim.fn.getpos("'>"))
  end

  local filepath = vim.fn.expand("%:p")
  local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local buffer_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  local target_buf = vim.api.nvim_get_current_buf()

  vim.ui.input({ prompt = "🤖 Claude: " }, function(prompt)
    if not prompt or prompt == "" then
      vim.notify("No instruction provided.", vim.log.levels.WARN, { title = "Claude" })
      return
    end

    local context_file = os.tmpname()
    local f = io.open(context_file, "w")
    f:write("CURRENT FILE: " .. filepath .. "\n\n")
    f:write("FULL BUFFER CONTENT:\n" .. buffer_content .. "\n\n")
    f:write("CURSOR POSITION: Line " .. cursor_row .. ", Column " .. cursor_col .. "\n\n")

    if is_visual then
      f:write("SELECTED TEXT (Lines " .. sel_start_row .. "-" .. sel_end_row .. "):\n" .. selection .. "\n\n")
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

    local script = vim.fn.stdpath("config") .. "/lua/claude/scripts/claude.sh"

    vim.notify("🤖 Claude: processing…", vim.log.levels.INFO, {
      id = NOTIF_ID,
      title = "Claude",
      timeout = false,
    })

    vim.system({ script, context_file, prompt }, { text = true }, function(result)
      vim.schedule(function()
        os.remove(context_file)

        if result.code ~= 0 then
          vim.notify(
            "Claude failed (exit " .. result.code .. "):\n" .. (result.stderr or ""),
            vim.log.levels.ERROR,
            { id = NOTIF_ID, title = "Claude", timeout = 5000 }
          )
          return
        end

        M._handle_output(result.stdout or "", {
          is_visual = is_visual,
          visual_mode = visual_mode,
          sel_end_row = sel_end_row,
          cursor_row = cursor_row,
          cursor_col = cursor_col,
          target_buf = target_buf,
        })
      end)
    end)
  end)
end

function M._handle_output(output, ctx)
  local lines = vim.split(output, "\n", { plain = true })
  local action = lines[1]
  local content_lines = {}
  for i = 2, #lines do
    if lines[i] ~= "" or i < #lines then
      table.insert(content_lines, lines[i])
    end
  end
  local content = table.concat(content_lines, "\n"):gsub("\n$", "")

  if action == "[ACTION:DISPLAY]" then
    local display_buf = vim.api.nvim_create_buf(false, true)
    local display_lines = vim.split(content, "\n", { plain = true })

    local width = math.min(80, vim.o.columns - 10)
    local height = math.min(#display_lines + 2, vim.o.lines - 10)

    vim.api.nvim_buf_set_lines(display_buf, 0, -1, false, display_lines)
    vim.bo[display_buf].filetype = "markdown"
    vim.bo[display_buf].bufhidden = "wipe"
    vim.bo[display_buf].modifiable = false

    local display_win = vim.api.nvim_open_win(display_buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = "rounded",
      title = " Claude Analysis ",
      title_pos = "center",
    })

    for _, key in ipairs({ "<Esc>", "q", "<CR>" }) do
      vim.keymap.set("n", key, function()
        if vim.api.nvim_win_is_valid(display_win) then
          vim.api.nvim_win_close(display_win, true)
        end
      end, { buffer = display_buf, nowait = true, silent = true })
    end

    vim.notify(
      "Claude analysis ready. Press <Esc>, q, or <Enter> to close.",
      vim.log.levels.INFO,
      { id = NOTIF_ID, title = "Claude", timeout = 3000 }
    )
    return
  end

  if not vim.api.nvim_buf_is_valid(ctx.target_buf) then
    vim.notify(
      "Claude: original buffer is no longer valid.",
      vim.log.levels.WARN,
      { id = NOTIF_ID, title = "Claude", timeout = 3000 }
    )
    return
  end

  vim.api.nvim_buf_call(ctx.target_buf, function()
    if ctx.is_visual then
      if action == "[ACTION:REPLACE]" then
        local save_reg = vim.fn.getreg('"')
        local save_regtype = vim.fn.getregtype('"')

        vim.fn.setreg('"', content, ctx.visual_mode)
        vim.cmd('normal! gv"_d')
        vim.cmd("normal! P")

        vim.fn.setreg('"', save_reg, save_regtype)
      elseif action == "[ACTION:INSERT_AFTER]" then
        local content_lines_new = vim.split(content, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(ctx.target_buf, ctx.sel_end_row, ctx.sel_end_row, false, content_lines_new)
      end
    else
      local content_lines_new = vim.split(content, "\n", { plain = true })
      vim.api.nvim_buf_set_text(
        ctx.target_buf,
        ctx.cursor_row - 1,
        ctx.cursor_col,
        ctx.cursor_row - 1,
        ctx.cursor_col,
        content_lines_new
      )
    end
  end)

  vim.notify(
    "Claude enhancement complete!",
    vim.log.levels.INFO,
    { id = NOTIF_ID, title = "Claude", timeout = 3000 }
  )
end

return M
