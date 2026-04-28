-- neogit-hunk-preview: peek a Neogit hunk in a side-by-side float.
--   * Left pane:  the hunk as it appears in Neogit's diff (same highlights).
--   * Right pane: the post-change file content for the hunk's range,
--                 rendered with the file's actual filetype.
--   The two panes' cursors are kept in sync.
--
-- Public API:
--   require("neogit-hunk-preview").peek()  -- in a NeogitStatus buffer
--
-- Behavior:
--   * Normal mode  -> shows the full hunk on the left and the full
--                     post-change line range on the right.
--   * Visual mode  -> shows the selected sub-range on the left and the
--                     mapped post-change lines on the right.
--
-- Inside the float:
--   q / <Esc>  close
--   <Tab>      toggle focus between the two panes

local M = {}

local NS = vim.api.nvim_create_namespace("neogit-hunk-preview_diff")

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "neogit-hunk-preview" })
end

local function neogit_status_instance()
  local ok, status_mod = pcall(require, "neogit.buffers.status")
  if not ok or type(status_mod.instance) ~= "function" then
    return nil
  end
  return status_mod.instance()
end

local function worktree_root()
  local ok, git = pcall(require, "neogit.lib.git")
  if not ok then
    return nil
  end
  local root = git.repo and git.repo.worktree_root
  if root and root ~= "" then
    return root
  end
  return nil
end

-- Same rules Neogit uses in lua/neogit/buffers/common.lua: pick line_hl_group
-- based on the leading character of the diff line.
local function highlight_for(line)
  if line:match("^@@") then
    return "NeogitHunkHeader"
  elseif line:match("^<<<<<<<") or line:match("^|||||||") or line:match("^=======") or line:match("^>>>>>>>") then
    return "NeogitHunkMergeHeader"
  end
  local p = line:sub(1, 1)
  if p == "+" then
    return "NeogitDiffAdd"
  elseif p == "-" then
    return "NeogitDiffDelete"
  else
    return "NeogitDiffContext"
  end
end

-- Mirror Neogit's add_line_highlight: a regular hl_group extmark spanning
-- to col 0 of the next line with hl_eol = true. This deliberately uses a
-- LOWER priority (190) than the inline-word and treesitter overlays so they
-- can paint on top. `line_hl_group` would default to priority 4096 and bury
-- everything.
local function apply_line_highlights(buf, lines)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for i, line in ipairs(lines) do
    vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, {
      hl_group = highlight_for(line),
      end_row = i,
      end_col = 0,
      hl_eol = true,
      priority = 190,
    })
  end
end

-- Treesitter syntax overlay (priority 210). Mirrors what Neogit does with
-- treesitter_diff_highlight: parse the stripped (no-prefix) content as the
-- file's language, then paint @capture extmarks on the buffer lines —
-- shifted by 1 col so they align with the diff prefix.
local function apply_treesitter_highlights(buf, lines, filepath)
  if not filepath or filepath == "" then
    return
  end
  local ft = vim.filetype.match({ filename = filepath })
  if not ft then
    return
  end
  local ok_get, lang = pcall(vim.treesitter.language.get_lang, ft)
  if not ok_get or not lang then
    return
  end
  if not pcall(vim.treesitter.language.inspect, lang) then
    return
  end

  local stripped, buf_rows = {}, {}
  for i, line in ipairs(lines) do
    local p = line:sub(1, 1)
    if p == "+" or p == "-" or p == " " then
      stripped[#stripped + 1] = line:sub(2)
      buf_rows[#stripped] = i - 1
    end
  end
  if #stripped == 0 then
    return
  end

  local source = table.concat(stripped, "\n")
  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not ok_parser or not parser then
    return
  end
  parser:parse()
  parser:for_each_tree(function(tree, ltree)
    local query = vim.treesitter.query.get(ltree:lang(), "highlights")
    if not query then
      return
    end
    local captures = query.captures
    for id, node in query:iter_captures(tree:root(), source) do
      local sr, sc, er, ec = node:range()
      for row = sr, er do
        local bl = buf_rows[row + 1]
        if bl then
          vim.api.nvim_buf_set_extmark(buf, NS, bl, (row == sr and sc or 0) + 1, {
            end_col = (row == er and ec or #stripped[row + 1]) + 1,
            hl_group = "@" .. captures[id],
            priority = 210,
          })
        end
      end
    end
  end)
end

-- Replicate Neogit's word-level inline diff highlights by reusing its
-- word_diff_spans helper. Walks groups of consecutive '-' lines followed by
-- consecutive '+' lines and pairs them index-by-index.
local function apply_inline_highlights(buf, lines)
  local ok, dh = pcall(require, "neogit.lib.diff_highlights")
  if not ok or type(dh.word_diff_spans) ~= "function" then
    return
  end

  local prefixes, stripped = {}, {}
  for k, line in ipairs(lines) do
    local p = line:sub(1, 1)
    if p == "+" or p == "-" or p == " " then
      prefixes[k] = p
      stripped[k] = line:sub(2)
    end
  end

  local MAX_DISTANCE = 0.6
  local n = #lines
  local i = 1
  while i <= n do
    local del_start = i
    while i <= n and prefixes[i] == "-" do
      i = i + 1
    end
    local add_start = i
    while i <= n and prefixes[i] == "+" do
      i = i + 1
    end

    local del_count = add_start - del_start
    local add_count = i - add_start

    for j = 0, math.min(del_count, add_count) - 1 do
      local old_spans, new_spans, distance = dh.word_diff_spans(stripped[del_start + j], stripped[add_start + j])
      if distance <= MAX_DISTANCE then
        for _, span in ipairs(old_spans) do
          vim.api.nvim_buf_set_extmark(buf, NS, (del_start + j) - 1, span[1] + 1, {
            end_col = span[2] + 1,
            hl_group = "NeogitDiffDeleteInline",
            priority = 220,
          })
        end
        for _, span in ipairs(new_spans) do
          vim.api.nvim_buf_set_extmark(buf, NS, (add_start + j) - 1, span[1] + 1, {
            end_col = span[2] + 1,
            hl_group = "NeogitDiffAddInline",
            priority = 220,
          })
        end
      end
    end

    if del_count == 0 and add_count == 0 then
      i = i + 1
    end
  end
end

-- Build cursor-mapping tables between the diff pane and the right pane.
-- left_to_right[L] = right pane line for left pane line L (nil for deletions/header).
-- right_to_left[R] = left pane line for right pane line R.
local function build_maps(hunk, idx_from, idx_to, has_header, disk_from)
  local left_to_right = {}
  local right_to_left = {}
  local offset = has_header and 1 or 0
  local nondel_count = 0
  for hi = 1, #hunk.lines do
    local prefix = hunk.lines[hi]:sub(1, 1)
    if prefix ~= "-" then
      nondel_count = nondel_count + 1
    end
    if hi >= idx_from and hi <= idx_to and prefix ~= "-" then
      local left_line = (hi - idx_from + 1) + offset
      local disk_line = hunk.disk_from + nondel_count - 1
      local right_line = disk_line - disk_from + 1
      left_to_right[left_line] = right_line
      right_to_left[right_line] = left_line
    end
  end
  return left_to_right, right_to_left
end

local function read_disk_range(file, from, to)
  local root = worktree_root()
  if not root or not file then
    return nil
  end
  local path = root .. "/" .. file
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, all = pcall(vim.fn.readfile, path)
  if not ok or type(all) ~= "table" then
    return nil
  end
  local out = {}
  for i = from, to do
    out[#out + 1] = all[i] or ""
  end
  return out
end

local function make_buf(lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  if filetype and filetype ~= "" then
    vim.bo[buf].filetype = filetype
  end
  return buf
end

local function setup_win_options(win)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = true
  -- Vim's built-in scroll binding handles mouse-wheel and <C-d>/<C-u>
  -- visual scroll sync at a level our autocmds can't reach (WinScrolled
  -- fires deferred and escapes 'eventignore' / flag-based guards). Both
  -- panes get scrollbind=true; opting into 'jump' aligns toplines when the
  -- binding first engages.
  vim.wo[win].scrollbind = true
end

-- Set cursor on `win` to `line` only if it differs from the current cursor —
-- this avoids triggering CursorMoved (and therefore avoids feedback loops in
-- the sync handlers).
local function quiet_set_cursor(win, line)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local total = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  line = math.max(1, math.min(total, line))
  local cur = vim.api.nvim_win_get_cursor(win)
  if cur[1] ~= line then
    pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
  end
end

local function open_pair(left, right, maps)
  local total_w = math.min(math.floor(vim.o.columns * 0.92), vim.o.columns - 4)
  local total_h = math.min(math.floor(vim.o.lines * 0.85), vim.o.lines - 4)
  local row = math.floor((vim.o.lines - total_h) / 2)
  local col = math.floor((vim.o.columns - total_w) / 2)
  local gap = 2
  local left_w = math.floor((total_w - gap) / 2)
  local right_w = total_w - left_w - gap

  local left_buf = make_buf(left.lines, nil)
  apply_line_highlights(left_buf, left.lines)
  apply_treesitter_highlights(left_buf, left.lines, left.filepath)
  apply_inline_highlights(left_buf, left.lines)
  local right_buf = make_buf(right.lines, right.filetype)

  local left_win = vim.api.nvim_open_win(left_buf, false, {
    relative = "editor",
    width = left_w,
    height = total_h,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " " .. left.title .. " ",
    title_pos = "center",
  })
  local right_win = vim.api.nvim_open_win(right_buf, true, {
    relative = "editor",
    width = right_w,
    height = total_h,
    col = col + left_w + gap,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " " .. right.title .. " ",
    title_pos = "center",
  })

  setup_win_options(left_win)
  setup_win_options(right_win)

  local closed = false
  local function close()
    if closed then
      return
    end
    closed = true
    for _, win in ipairs({ left_win, right_win }) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
  end

  local function focus_other()
    local cur = vim.api.nvim_get_current_win()
    local target = (cur == left_win) and right_win or left_win
    if vim.api.nvim_win_is_valid(target) then
      vim.api.nvim_set_current_win(target)
    end
  end

  for _, buf in ipairs({ left_buf, right_buf }) do
    vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, silent = true, desc = "neogit-hunk-preview: close" })
    vim.keymap.set(
      "n",
      "<Esc>",
      close,
      { buffer = buf, nowait = true, silent = true, desc = "neogit-hunk-preview: close" }
    )
    vim.keymap.set(
      "n",
      "<Tab>",
      focus_other,
      { buffer = buf, nowait = true, silent = true, desc = "neogit-hunk-preview: focus other pane" }
    )
  end

  -- Cursor sync via CursorMoved. Visual scroll sync (mouse wheel,
  -- <C-d>/<C-u>) is handled by 'scrollbind' on the windows themselves —
  -- WinScrolled fires deferred and isn't reliably suppressible by
  -- 'eventignore' or guard flags, which is why a previous WinScrolled-based
  -- sync looped. quiet_set_cursor is a no-op when the cursor is already on
  -- the target line, so the two CursorMoved handlers don't recurse.
  local function snap_left_to_right(L)
    for k = L, 1, -1 do
      if maps.left_to_right[k] then
        return maps.left_to_right[k]
      end
    end
    return nil
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = left_buf,
    callback = function()
      local L = vim.api.nvim_win_get_cursor(left_win)[1]
      local R = snap_left_to_right(L)
      if R then
        quiet_set_cursor(right_win, R)
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = right_buf,
    callback = function()
      local R = vim.api.nvim_win_get_cursor(right_win)[1]
      local L = maps.right_to_left[R]
      if L then
        quiet_set_cursor(left_win, L)
      end
    end,
  })

  for _, win in ipairs({ left_win, right_win }) do
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = close,
    })
  end
end

function M.peek()
  local status = neogit_status_instance()
  if not status or not status.buffer then
    notify("Neogit status buffer is not active", vim.log.levels.WARN)
    return
  end

  local v = vim.fn.line("v")
  local c = vim.fn.line(".")
  local sel_first = math.min(v, c)
  local sel_last = math.max(v, c)
  local is_visual = sel_first ~= sel_last

  local ui = status.buffer.ui
  local hunk_obj
  local diff_lines
  local idx_from, idx_to
  local has_header
  local sub_label = ""

  if is_visual then
    local item = ui:get_item_under_cursor()
    if not item then
      notify("Selection is not inside a file/hunk")
      return
    end
    local hunks = ui:item_hunks(item, sel_first, sel_last, true)
    if not hunks or #hunks == 0 then
      notify("No hunk in selection")
      return
    end
    local sh = hunks[1]
    hunk_obj = sh.hunk
    idx_from = math.max(1, sh.from)
    idx_to = math.min(#hunk_obj.lines, sh.to)
    diff_lines = {}
    for i = idx_from, idx_to do
      diff_lines[#diff_lines + 1] = hunk_obj.lines[i]
    end
    has_header = false
    sub_label = string.format(" [sel %d-%d]", idx_from, idx_to)
  else
    local stagable = ui:get_hunk_or_filename_under_cursor()
    if not stagable or not stagable.hunk then
      notify("No hunk under cursor")
      return
    end
    hunk_obj = stagable.hunk
    idx_from = 1
    idx_to = #hunk_obj.lines
    diff_lines = vim.list_extend({ hunk_obj.line }, hunk_obj.lines)
    has_header = true
  end

  local file = hunk_obj.file or "?"
  local filetype = vim.filetype.match({ filename = file }) or ""

  -- Compute the post-change line range for this slice of the hunk.
  local d_first, d_last
  do
    local nondel = 0
    for hi = 1, idx_to do
      if hunk_obj.lines[hi]:sub(1, 1) ~= "-" then
        nondel = nondel + 1
        if hi >= idx_from then
          local d = hunk_obj.disk_from + nondel - 1
          d_first = d_first or d
          d_last = d
        end
      end
    end
  end

  local right_lines, right_title, maps
  if d_first and d_last then
    right_lines = read_disk_range(file, d_first, d_last)
    if right_lines then
      right_title = string.format("%s  %d-%d", file, d_first, d_last)
    else
      right_lines = { "(could not read " .. file .. " from worktree)" }
      right_title = file
    end
    local l2r, r2l = build_maps(hunk_obj, idx_from, idx_to, has_header, d_first)
    maps = { left_to_right = l2r, right_to_left = r2l }
  else
    right_lines = { "(no post-change lines in this range — only deletions)" }
    right_title = file
    maps = { left_to_right = {}, right_to_left = {} }
  end

  open_pair({
    title = "diff" .. sub_label,
    lines = diff_lines,
    filepath = file,
  }, {
    title = right_title,
    lines = right_lines,
    filetype = filetype,
  }, maps)
end

-- Install buffer-local mappings on NeogitStatus buffers.
function M.setup(opts)
  opts = opts or {}
  local key = opts.key or "<leader>p"

  local group = vim.api.nvim_create_augroup("neogit-hunk-preview", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "NeogitStatus",
    callback = function(args)
      local map_opts = { buffer = args.buf, silent = true, desc = "neogit-hunk-preview: peek hunk" }
      vim.keymap.set("n", key, "<cmd>lua require('neogit-hunk-preview').peek()<CR>", map_opts)
      vim.keymap.set("x", key, "<cmd>lua require('neogit-hunk-preview').peek()<CR>", map_opts)
    end,
  })
end

return M
