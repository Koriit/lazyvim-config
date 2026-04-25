local M = {}

local function open_popup(text, title)
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end
  local width = 0
  for _, l in ipairs(lines) do
    if #l > width then
      width = #l
    end
  end
  width = math.min(math.max(width + 2, 30), math.floor(vim.o.columns * 0.6))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.4))
  if height < 1 then
    height = 1
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    width = width,
    height = height,
    col = 1,
    row = 1,
    style = "minimal",
    border = "rounded",
    title = title or " sidenote ",
    title_pos = "center",
    focusable = true,
  })

  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Close when the user navigates away from the float (e.g. <C-w>w to a
  -- different window). bufhidden=wipe handles the buffer cleanup.
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = close,
  })

  for _, key in ipairs({ "<Esc>", "q", "<CR>" }) do
    vim.keymap.set("n", key, close, { buffer = buf, nowait = true, silent = true })
  end

  return buf, win
end

function M.show(comments, body_for)
  if not comments or #comments == 0 then
    vim.notify("No sidenote at cursor", vim.log.levels.INFO, { title = "sidenote" })
    return
  end
  body_for = body_for or function(c)
    return c.comment or ""
  end
  if #comments == 1 then
    local c = comments[1]
    open_popup(body_for(c), " sidenote: " .. (c.selectedText or "") .. " ")
    return
  end
  local items = {}
  for _, c in ipairs(comments) do
    table.insert(items, c)
  end
  vim.ui.select(items, {
    prompt = "sidenote: choose",
    format_item = function(c)
      local excerpt = (c.selectedText or ""):gsub("\n", " ")
      if #excerpt > 60 then
        excerpt = excerpt:sub(1, 57) .. "..."
      end
      return excerpt
    end,
  }, function(choice)
    if not choice then
      return
    end
    open_popup(body_for(choice), " sidenote: " .. (choice.selectedText or "") .. " ")
  end)
end

return M
