local M = {}

local function open_window(initial_lines, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buftype = "acwrite"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines or { "" })
  vim.bo[buf].modified = false

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.4)
  if width < 40 then
    width = math.min(60, vim.o.columns - 4)
  end
  if height < 8 then
    height = math.min(15, vim.o.lines - 4)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = title or " sidenote ",
    title_pos = "center",
  })

  vim.api.nvim_buf_set_name(buf, "sidenote://" .. tostring(buf))
  return buf, win
end

local function buffer_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.open(opts)
  opts = opts or {}
  local initial = opts.initial or ""
  local on_save = opts.on_save
  local on_cancel = opts.on_cancel
  local on_delete = opts.on_delete
  local title = opts.title or " sidenote "
  local had_body = opts.had_body == true

  local lines = vim.split(initial, "\n", { plain = true })
  local buf, win = open_window(lines, title)

  local closed = false
  local close_window = function()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  local do_save = function()
    local text = buffer_text(buf)
    local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
      if had_body then
        local choice = vim.fn.confirm("Empty body — delete this comment?", "&Yes\n&No", 2)
        if choice == 1 then
          close_window()
          if on_delete then
            on_delete()
          end
          return
        end
        return
      else
        close_window()
        if on_cancel then
          on_cancel()
        end
        return
      end
    end
    close_window()
    if on_save then
      on_save(text)
    end
  end

  local do_cancel = function()
    close_window()
    if on_cancel then
      on_cancel()
    end
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
      do_save()
    end,
  })

  vim.keymap.set("n", "<CR>", do_save, { buffer = buf, nowait = true, silent = true, desc = "sidenote: save" })
  vim.keymap.set("n", "q", do_cancel, { buffer = buf, nowait = true, silent = true, desc = "sidenote: cancel" })
  vim.keymap.set("n", "<Esc>", do_cancel, { buffer = buf, nowait = true, silent = true, desc = "sidenote: cancel" })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if not closed then
        closed = true
        if on_cancel then
          on_cancel()
        end
      end
    end,
  })

  vim.cmd("startinsert")
  return buf, win
end

return M
