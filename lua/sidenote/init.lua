local M = {}

local uv = vim.uv or vim.loop

local vault_mod = require("sidenote.vault")
local storage = require("sidenote.storage")
local anchor = require("sidenote.anchor")
local highlight = require("sidenote.highlight")
local float = require("sidenote.ui.float")
local hover = require("sidenote.ui.hover")
local browse = require("sidenote.ui.browse")

local NOTIF_TITLE = "sidenote"
local AUGROUP = "Sidenote"

local state = {
  initialized = false,
  show_resolved = false,
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = NOTIF_TITLE })
end

local function require_markdown()
  if vim.bo.filetype ~= "markdown" then
    notify("sidenote: markdown buffers only", vim.log.levels.WARN)
    return false
  end
  return true
end

local function bit_set(byte, mask, set_bits)
  local ok, bit = pcall(require, "bit")
  if ok and bit then
    return bit.bor(bit.band(byte, mask), set_bits)
  end
  return (byte % (mask + 1)) + set_bits
end

local function uuidv4()
  local bytes = uv.random(16, 0)
  if not bytes or #bytes ~= 16 then
    local fallback = vim.fn.system("uuidgen")
    if vim.v.shell_error == 0 then
      return (fallback:gsub("%s+", ""):lower())
    end
    error("sidenote: cannot generate UUID")
  end
  local b = { bytes:byte(1, 16) }
  b[7] = bit_set(b[7], 0x0F, 0x40)
  b[9] = bit_set(b[9], 0x3F, 0x80)
  return string.format(
    "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    b[1],
    b[2],
    b[3],
    b[4],
    b[5],
    b[6],
    b[7],
    b[8],
    b[9],
    b[10],
    b[11],
    b[12],
    b[13],
    b[14],
    b[15],
    b[16]
  )
end

local function now_ms()
  local sec, usec = uv.gettimeofday()
  return sec * 1000 + math.floor((usec or 0) / 1000)
end

local function bufnr_path(bufnr)
  local n = vim.api.nvim_buf_get_name(bufnr)
  if n == "" then
    return nil
  end
  return vim.fn.fnamemodify(n, ":p")
end

local function ctx_for_buffer(bufnr, opts)
  opts = opts or {}
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local abs = bufnr_path(bufnr)
  if not abs then
    return nil
  end
  local vault, created = vault_mod.resolve_for_buffer(bufnr, opts)
  if not vault then
    return nil
  end
  if not opts.no_init then
    vault_mod.ensure_initialized(vault)
  end
  local data_path = vault_mod.data_path(vault)
  local rel = vault_mod.relative_path(vault, abs)
  return {
    bufnr = bufnr,
    abs_path = abs,
    vault = vault,
    data_path = data_path,
    rel_path = vault_mod.to_posix(rel),
    created = created,
  }
end

local function comments_for_buffer(data, rel_path)
  local out = {}
  for _, c in ipairs(data.comments or {}) do
    if c.filePath == rel_path then
      table.insert(out, c)
    end
  end
  return out
end

local function refresh_buffer_render(ctx)
  if not ctx then
    return
  end
  local data = storage.load(ctx.data_path)
  highlight.ensure_highlight(data)
  local mine = comments_for_buffer(data, ctx.rel_path)
  highlight.render(ctx.bufnr, mine, { show_resolved = state.show_resolved })
end

local function refresh_all_markdown_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "markdown" then
      local ctx = ctx_for_buffer(bufnr, { no_init = true })
      if ctx then
        refresh_buffer_render(ctx)
      end
    end
  end
end

local function find_at_cursor(ctx, data)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local col = cursor[2]
  local matches = {}
  for _, c in ipairs(data.comments or {}) do
    if c.filePath == ctx.rel_path then
      local sl = c.startLine
      local el = c.endLine or sl
      local sc = c.startChar or 0
      local ec = c.endChar or sc
      local hit = false
      if sl == el then
        if line == sl and col >= sc and col <= ec then
          hit = true
        end
      else
        if line == sl and col >= sc then
          hit = true
        elseif line > sl and line < el then
          hit = true
        elseif line == el and col <= ec then
          hit = true
        end
      end
      if hit then
        table.insert(matches, c)
      end
    end
  end
  return matches
end

local function find_at_cursor_with_resolved(ctx, data)
  return find_at_cursor(ctx, data)
end

local function persist_with(ctx, mutator)
  storage.update(ctx.data_path, mutator)
  refresh_buffer_render(ctx)
end

local function strip_md_ext(s)
  return (s:gsub("%.md$", ""))
end

local function sidecar_path(vault, settings, rel_path)
  local folder = (settings and settings.markdownFolder) or "side-note-comments"
  local mangled = strip_md_ext(rel_path):gsub("/", "__")
  return vault .. "/" .. folder .. "/" .. mangled .. "-sidenote.md"
end

local function read_sidecar(vault, settings, rel_path)
  local path = sidecar_path(vault, settings, rel_path)
  local fd = uv.fs_open(path, "r", 420)
  if not fd then
    return {}
  end
  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return {}
  end
  local raw = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  if not raw or raw == "" then
    return {}
  end
  local map = {}
  local blocks = vim.split(raw, "\n%-%-%-\n", { plain = false })
  for _, block in ipairs(blocks) do
    local key = block:match("<!%-%- side%-note:([^%s]+) %-%->")
    if key then
      local body = block:gsub(".-<!%-%- side%-note:[^%s]+ %-%->%s*\n?", "", 1)
      body = body:gsub("^%s+", ""):gsub("%s+$", "")
      map[key] = body
    end
  end
  return map
end

local function body_for_factory(ctx, data)
  local sidecar = read_sidecar(ctx.vault, data, ctx.rel_path)
  return function(c)
    if c.id and sidecar[c.id] then
      return sidecar[c.id]
    end
    if c.timestamp and sidecar[tostring(c.timestamp)] then
      return sidecar[tostring(c.timestamp)]
    end
    return c.comment or ""
  end
end

local function line_byte_length(bufnr, lnum_1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, lnum_1 - 1, lnum_1, false)
  return #(lines[1] or "")
end

local function visual_range()
  -- Read the LIVE visual selection. Under <Cmd>-bound visual mappings (lazy.nvim
  -- `mode = "x"` keys do this), we are still in visual mode when this runs, so
  -- the '< / '> marks are stale or unset. Use getpos("v") (visual anchor) and
  -- getpos(".") (cursor) which return the active selection endpoints.
  local bufnr = vim.api.nvim_get_current_buf()
  local a = vim.fn.getpos("v")
  local b = vim.fn.getpos(".")

  -- Normalize so (a) is start, (b) is end.
  if (a[2] > b[2]) or (a[2] == b[2] and a[3] > b[3]) then
    a, b = b, a
  end

  local mode = vim.fn.mode()
  local start_row = a[2] - 1
  local end_row = b[2] - 1
  local start_col, end_col

  if mode == "V" then
    -- Line-visual: span from col 0 of first line through end-of-line of last line.
    start_col = 0
    end_col = line_byte_length(bufnr, b[2])
  elseif mode == "\22" then
    -- Block-visual: treat as multi-line full-line span (col 0..end of last line).
    start_col = 0
    end_col = line_byte_length(bufnr, b[2])
  else
    -- Char-visual ('v') or fallback when no visual mode is active (stale '< '>).
    start_col = a[3] - 1
    -- b[3] is 1-indexed inclusive end; we want 0-indexed exclusive end, which
    -- equals b[3]. Clamp to line length to handle vim.v.maxcol at EOL.
    local end_line_len = line_byte_length(bufnr, b[2])
    end_col = math.min(b[3], end_line_len)
  end

  return start_row, start_col, end_row, end_col
end

-- Exposed for headless unit tests; intentionally underscore-prefixed.
M._test_visual_range = visual_range

local function selection_text(bufnr, sr, sc, er, ec)
  local lines = vim.api.nvim_buf_get_lines(bufnr, sr, er + 1, false)
  if #lines == 0 then
    return ""
  end
  if sr == er then
    return string.sub(lines[1], sc + 1, ec)
  end
  local parts = {}
  -- First line: from sc to end of line.
  table.insert(parts, string.sub(lines[1], sc + 1))
  -- Middle lines: whole line.
  for i = 2, #lines - 1 do
    table.insert(parts, lines[i] or "")
  end
  -- Last line: from start to ec (ec is 0-indexed exclusive).
  table.insert(parts, string.sub(lines[#lines] or "", 1, ec))
  return table.concat(parts, "\n")
end

-- Exposed for headless unit tests; intentionally underscore-prefixed.
M._test_selection_text = selection_text

local function create_from_visual(ctx)
  local sr, sc, er, ec = visual_range()
  local text = selection_text(ctx.bufnr, sr, sc, er, ec)
  if #text < 3 then
    notify("sidenote: selection too short, min 3 chars", vim.log.levels.WARN)
    return
  end

  local data = storage.load(ctx.data_path)
  for _, c in ipairs(data.comments) do
    if
      c.filePath == ctx.rel_path
      and c.startLine == sr
      and c.startChar == sc
      and c.endLine == er
      and c.endChar == ec
    then
      M.edit_comment(ctx, c)
      return
    end
  end

  float.open({
    initial = "",
    title = " sidenote: new ",
    had_body = false,
    on_save = function(body)
      persist_with(ctx, function(d)
        local comment = {
          id = uuidv4(),
          filePath = ctx.rel_path,
          startLine = sr,
          startChar = sc,
          endLine = er,
          endChar = ec,
          selectedText = text,
          selectedTextHash = anchor.sha256(text),
          comment = body,
          timestamp = now_ms(),
        }
        table.insert(d.comments, comment)
        return d
      end)
      notify("sidenote: created", vim.log.levels.INFO)
    end,
  })
end

function M.edit_comment(ctx, comment)
  float.open({
    initial = comment.comment or "",
    title = " sidenote: edit ",
    had_body = (comment.comment ~= nil and comment.comment ~= ""),
    on_save = function(body)
      persist_with(ctx, function(d)
        for _, c in ipairs(d.comments) do
          if c.id == comment.id then
            c.comment = body
            c.timestamp = now_ms()
          end
        end
        return d
      end)
      notify("sidenote: updated", vim.log.levels.INFO)
    end,
    on_delete = function()
      persist_with(ctx, function(d)
        local kept = {}
        for _, c in ipairs(d.comments) do
          if c.id ~= comment.id then
            table.insert(kept, c)
          end
        end
        d.comments = kept
        return d
      end)
      notify("sidenote: deleted", vim.log.levels.INFO)
    end,
  })
end

function M.create_or_edit_visual()
  if not require_markdown() then
    return
  end
  local ctx = ctx_for_buffer(vim.api.nvim_get_current_buf(), { create_on_miss = true })
  if not ctx then
    notify("sidenote: cannot determine vault", vim.log.levels.ERROR)
    return
  end
  create_from_visual(ctx)
end

function M.create_or_edit_cursor()
  if not require_markdown() then
    return
  end
  local ctx = ctx_for_buffer(vim.api.nvim_get_current_buf(), { create_on_miss = true })
  if not ctx then
    notify("sidenote: cannot determine vault", vim.log.levels.ERROR)
    return
  end
  local data = storage.load(ctx.data_path)
  local matches = find_at_cursor(ctx, data)
  if #matches == 0 then
    notify("sidenote: no comment under cursor", vim.log.levels.INFO)
    return
  end
  M.edit_comment(ctx, matches[1])
end

function M.delete_at_cursor()
  if not require_markdown() then
    return
  end
  local ctx = ctx_for_buffer(vim.api.nvim_get_current_buf())
  if not ctx then
    return
  end
  local data = storage.load(ctx.data_path)
  local matches = find_at_cursor(ctx, data)
  if #matches == 0 then
    notify("sidenote: no comment under cursor", vim.log.levels.INFO)
    return
  end
  local target = matches[1]
  local choice = vim.fn.confirm("Delete this sidenote?", "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  persist_with(ctx, function(d)
    local kept = {}
    for _, c in ipairs(d.comments) do
      if c.id ~= target.id then
        table.insert(kept, c)
      end
    end
    d.comments = kept
    return d
  end)
  notify("sidenote: deleted", vim.log.levels.INFO)
end

function M.toggle_show_resolved(opts)
  opts = opts or {}
  state.show_resolved = not state.show_resolved
  refresh_all_markdown_buffers()
  if not opts.silent then
    notify(string.format("sidenote: show resolved = %s", tostring(state.show_resolved)), vim.log.levels.INFO)
  end
end

function M.toggle_resolved_at_cursor()
  if not require_markdown() then
    return
  end
  local ctx = ctx_for_buffer(vim.api.nvim_get_current_buf())
  if not ctx then
    return
  end
  local data = storage.load(ctx.data_path)
  local matches = find_at_cursor_with_resolved(ctx, data)
  if #matches == 0 then
    notify("sidenote: no comment under cursor", vim.log.levels.INFO)
    return
  end
  local target = matches[1]
  persist_with(ctx, function(d)
    for _, c in ipairs(d.comments) do
      if c.id == target.id then
        local newval = not (c.resolved == true)
        c.resolved = newval
        c.resolvedAt = newval and now_ms() or vim.NIL
      end
    end
    return d
  end)
  notify("sidenote: toggled resolved", vim.log.levels.INFO)
end

function M.quicklook()
  if not require_markdown() then
    return
  end
  local ctx = ctx_for_buffer(vim.api.nvim_get_current_buf())
  if not ctx then
    return
  end
  local data = storage.load(ctx.data_path)
  local matches = find_at_cursor(ctx, data)
  if #matches == 0 then
    notify("sidenote: no comment under cursor", vim.log.levels.INFO)
    return
  end
  hover.show(matches, body_for_factory(ctx, data))
end

function M.browse()
  if not require_markdown() then
    return
  end
  local ctx = ctx_for_buffer(vim.api.nvim_get_current_buf())
  if not ctx then
    return
  end
  local data = storage.load(ctx.data_path)
  local mine = comments_for_buffer(data, ctx.rel_path)
  local body_for = body_for_factory(ctx, data)

  local jump_to = function(c)
    local line = (c.startLine or 0) + 1
    local col = c.startChar or 0
    pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
    M.edit_comment(ctx, c)
  end

  local delete = function(c)
    local choice = vim.fn.confirm("Delete this sidenote?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return
    end
    persist_with(ctx, function(d)
      local kept = {}
      for _, x in ipairs(d.comments) do
        if x.id ~= c.id then
          table.insert(kept, x)
        end
      end
      d.comments = kept
      return d
    end)
    notify("sidenote: deleted", vim.log.levels.INFO)
    M.browse()
  end

  local toggle_resolved = function(c)
    persist_with(ctx, function(d)
      for _, x in ipairs(d.comments) do
        if x.id == c.id then
          local newval = not (x.resolved == true)
          x.resolved = newval
          x.resolvedAt = newval and now_ms() or vim.NIL
        end
      end
      return d
    end)
    M.browse()
  end

  local toggle_show_resolved = function()
    M.toggle_show_resolved({ silent = true })
    M.browse()
  end

  browse.open(mine, {
    show_resolved = state.show_resolved,
    sort_order = data.commentSortOrder or "position",
    body_for = body_for,
    file = ctx.abs_path,
    on_pick = jump_to,
    on_delete = delete,
    on_toggle_resolved = toggle_resolved,
    on_toggle_show_resolved = toggle_show_resolved,
  })
end

local function find_visible_comments(ctx, data)
  local out = {}
  for _, c in ipairs(data.comments or {}) do
    local hidden = c.resolved == true and not state.show_resolved
    if c.filePath == ctx.rel_path and not hidden and c.isOrphaned ~= true then
      table.insert(out, c)
    end
  end
  table.sort(out, function(a, b)
    if a.startLine ~= b.startLine then
      return a.startLine < b.startLine
    end
    return (a.startChar or 0) < (b.startChar or 0)
  end)
  return out
end

local function navigate(direction)
  if not require_markdown() then
    return
  end
  local ctx = ctx_for_buffer(vim.api.nvim_get_current_buf())
  if not ctx then
    return
  end
  local data = storage.load(ctx.data_path)
  local list = find_visible_comments(ctx, data)
  if #list == 0 then
    notify("sidenote: no comments in buffer", vim.log.levels.INFO)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cur_line = cursor[1] - 1
  local cur_col = cursor[2]
  local target = nil
  if direction == 1 then
    for _, c in ipairs(list) do
      if c.startLine > cur_line or (c.startLine == cur_line and (c.startChar or 0) > cur_col) then
        target = c
        break
      end
    end
    if not target then
      target = list[1]
      notify("sidenote: wrapped to first", vim.log.levels.INFO)
    end
  else
    for i = #list, 1, -1 do
      local c = list[i]
      if c.startLine < cur_line or (c.startLine == cur_line and (c.startChar or 0) < cur_col) then
        target = c
        break
      end
    end
    if not target then
      target = list[#list]
      notify("sidenote: wrapped to last", vim.log.levels.INFO)
    end
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { target.startLine + 1, target.startChar or 0 })
end

function M.goto_next()
  navigate(1)
end

function M.goto_prev()
  navigate(-1)
end

local function on_buf_write_post(ev)
  local bufnr = ev.buf
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].filetype ~= "markdown" then
    return
  end
  local ctx = ctx_for_buffer(bufnr, { no_init = true })
  if not ctx then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  storage.update(ctx.data_path, function(d)
    for _, c in ipairs(d.comments or {}) do
      if c.filePath == ctx.rel_path then
        local match = anchor.resolve(lines, c)
        anchor.apply_resolution(c, match)
      end
    end
    return d
  end)
  refresh_buffer_render(ctx)
end

local function on_buf_read_post(ev)
  local bufnr = ev.buf
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].filetype ~= "markdown" then
    return
  end
  local ctx = ctx_for_buffer(bufnr, { no_init = true })
  if not ctx then
    return
  end
  refresh_buffer_render(ctx)
end

local function on_buf_file_post(ev)
  local bufnr = ev.buf
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].filetype ~= "markdown" then
    return
  end
  local old = ev.match or ev.file
  if not old or old == "" then
    return
  end
  local new_abs = bufnr_path(bufnr)
  if not new_abs then
    return
  end
  local vault = vault_mod.find_for_path(new_abs) or vault_mod.find_for_path(old)
  if not vault then
    return
  end
  local data_path = vault_mod.data_path(vault)
  local old_rel = vault_mod.to_posix(vault_mod.relative_path(vault, old))
  local new_rel = vault_mod.to_posix(vault_mod.relative_path(vault, new_abs))
  if old_rel == new_rel then
    return
  end
  storage.update(data_path, function(d)
    for _, c in ipairs(d.comments or {}) do
      if c.filePath == old_rel then
        c.filePath = new_rel
      end
    end
    return d
  end)
end

function M.setup(opts)
  if state.initialized then
    return
  end
  state.initialized = true
  state.opts = opts or {}

  highlight.ensure_highlight(vault_mod.default_settings())

  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    pattern = "*.md",
    callback = on_buf_read_post,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.md",
    callback = on_buf_write_post,
  })
  vim.api.nvim_create_autocmd("BufFilePost", {
    group = group,
    pattern = "*.md",
    callback = on_buf_file_post,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      highlight.ensure_highlight(vault_mod.default_settings())
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "markdown" then
      pcall(on_buf_read_post, { buf = bufnr })
    end
  end
end

return M
