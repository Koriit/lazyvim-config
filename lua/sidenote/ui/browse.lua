local M = {}

local function format_excerpt(text, n)
  if not text then
    return ""
  end
  local s = text:gsub("\n", " ")
  if #s > n then
    s = s:sub(1, n - 3) .. "..."
  end
  return s
end

local function build_items(comments, show_resolved, body_for)
  local out = {}
  for _, c in ipairs(comments) do
    if show_resolved or c.resolved ~= true then
      local excerpt = format_excerpt(c.selectedText or "", 40)
      local body = body_for and body_for(c) or (c.comment or "")
      local first_body_line = (body:gsub("\n.*", ""))
      local body_excerpt = format_excerpt(first_body_line, 60)
      local r_flag = c.resolved == true and "R" or " "
      local o_flag = c.isOrphaned == true and "O" or " "
      local flags = r_flag .. o_flag
      local label = string.format(
        "%s %4d:%-3d %s ▸ %s",
        flags,
        (c.startLine or 0) + 1,
        (c.startChar or 0) + 1,
        body_excerpt,
        excerpt
      )
      table.insert(out, {
        label = label,
        comment = c,
      })
    end
  end
  return out
end

local function sort_items(items, sort_order)
  if sort_order == "timestamp" then
    table.sort(items, function(a, b)
      return (a.comment.timestamp or 0) < (b.comment.timestamp or 0)
    end)
    return
  end
  table.sort(items, function(a, b)
    local al = a.comment.startLine or 0
    local bl = b.comment.startLine or 0
    if al ~= bl then
      return al < bl
    end
    return (a.comment.startChar or 0) < (b.comment.startChar or 0)
  end)
end

local function fallback_select(items, on_pick)
  if #items == 0 then
    vim.notify("No sidenotes for this file", vim.log.levels.INFO, { title = "sidenote" })
    return
  end
  vim.ui.select(items, {
    prompt = "sidenote: pick (CR jump+edit)",
    format_item = function(it)
      return it.label
    end,
  }, function(choice)
    if choice and on_pick then
      on_pick(choice.comment)
    end
  end)
end

local MAX_COMMENT_LINES = 12

local function format_timestamp(ts)
  if type(ts) ~= "number" or ts <= 0 then
    return ""
  end
  -- timestamps are milliseconds
  return os.date("%Y-%m-%d %H:%M:%S", math.floor(ts / 1000))
end

local function build_virt_lines(item)
  local c = (item and item.comment) or {}
  local row = (c.startLine or 0) + 1
  local col = (c.startChar or 0) + 1

  local badges = {}
  if c.resolved == true then
    table.insert(badges, "resolved")
  end
  if c.isOrphaned == true then
    table.insert(badges, "orphaned")
  end
  table.insert(badges, string.format("line %d:%d", row, col))
  local ts = format_timestamp(c.timestamp)
  if ts ~= "" then
    table.insert(badges, ts)
  end
  local header = string.format("┌─ sidenote (%s)", table.concat(badges, ", "))

  local body = c.comment or ""
  local body_lines = body == "" and { "(no comment body)" } or vim.split(body, "\n", { plain = true })

  local truncated_count = 0
  if #body_lines > MAX_COMMENT_LINES then
    truncated_count = #body_lines - MAX_COMMENT_LINES
    local trimmed = {}
    for i = 1, MAX_COMMENT_LINES do
      trimmed[i] = body_lines[i]
    end
    body_lines = trimmed
  end

  local virt_lines = {}
  table.insert(virt_lines, { { header, "Comment" } })
  for _, l in ipairs(body_lines) do
    table.insert(virt_lines, { { "│ ", "Comment" }, { l, "NormalFloat" } })
  end
  if truncated_count > 0 then
    table.insert(virt_lines, {
      { "│ ", "Comment" },
      { string.format("… (%d more line%s)", truncated_count, truncated_count == 1 and "" or "s"), "Comment" },
    })
  end
  table.insert(virt_lines, { { "└─", "Comment" } })
  return virt_lines
end

local function render_preview(ctx)
  local item = ctx.item
  local c = (item and item.comment) or {}
  local file = item and item.file
  local ns = vim.api.nvim_create_namespace("sidenote.preview")
  local virt_lines = build_virt_lines(item)

  -- Always reset snacks's preview state first so it doesn't think a buffer we
  -- mutated last round is still the "loaded file" for this round.
  if ctx.preview and ctx.preview.reset then
    pcall(function()
      ctx.preview:reset()
    end)
  end

  -- Read file lines directly (no buffer involvement) for the resolve check.
  local file_lines
  if file and file ~= "" and vim.fn.filereadable(file) == 1 then
    local ok_read, read = pcall(vim.fn.readfile, file)
    if ok_read and type(read) == "table" then
      file_lines = read
    end
  end

  -- Stage 1 only: cheap, doesn't freeze. Stage 2 runs on BufWritePost.
  local resolved
  if file_lines and c.selectedText then
    local ok_anchor, anchor = pcall(require, "sidenote.anchor")
    if ok_anchor and anchor then
      local ok_resolve, match = pcall(anchor.resolve_neighborhood, file_lines, c)
      if ok_resolve then
        resolved = match
      end
    end
  end

  if resolved and file_lines then
    -- Load file content ourselves via snacks's API so each render is
    -- self-contained. (snacks's preview.file path-caches by ctx.prev — when
    -- adjacent items target the same file, it skips reload, and any earlier
    -- buffer mutation we did would leak forward.)
    if ctx.preview and ctx.preview.set_title then
      pcall(function()
        ctx.preview:set_title(vim.fn.fnamemodify(file, ":t"))
      end)
    end
    if ctx.preview and ctx.preview.set_lines then
      pcall(function()
        ctx.preview:set_lines(file_lines)
      end)
    end
    if ctx.preview and ctx.preview.highlight then
      pcall(function()
        ctx.preview:highlight({ ft = vim.filetype.match({ filename = file }) or "markdown", buf = ctx.buf })
      end)
    end

    vim.api.nvim_buf_clear_namespace(ctx.buf, ns, 0, -1)
    local line_count = vim.api.nvim_buf_line_count(ctx.buf)
    local anchor_row0 = resolved.startLine
    if anchor_row0 >= 0 and anchor_row0 < line_count then
      pcall(vim.api.nvim_buf_set_extmark, ctx.buf, ns, anchor_row0, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
      })
      local file_line = file_lines[anchor_row0 + 1] or ""
      local line_len = #file_line
      local s_col = math.min(resolved.startChar or 0, line_len)
      local e_col = math.min(math.max(resolved.endChar or s_col, s_col), line_len)
      pcall(vim.api.nvim_buf_set_extmark, ctx.buf, ns, anchor_row0, s_col, {
        end_row = anchor_row0,
        end_col = e_col,
        hl_group = "SideNoteHighlight",
        hl_mode = "combine",
        priority = 200,
      })
      if ctx.win and vim.api.nvim_win_is_valid(ctx.win) then
        pcall(vim.api.nvim_win_set_cursor, ctx.win, { anchor_row0 + 1, s_col })
        pcall(vim.api.nvim_win_call, ctx.win, function()
          vim.cmd("normal! zz")
        end)
      end
    end
    return
  end

  -- Lost anchor: render comment + header + original selection as real buffer
  -- lines. Avoids virt_lines display quirks at the top of the buffer and
  -- handles multi-line comment bodies cleanly.
  local body_lines = vim.split(c.comment or "", "\n", { plain = true })
  if #body_lines == 0 or (body_lines[1] == "" and #body_lines == 1) then
    body_lines = { "(no comment body)" }
  end

  local sel_lines = vim.split(c.selectedText or "", "\n", { plain = true })
  if #sel_lines == 0 or (sel_lines[1] == "" and #sel_lines == 1) then
    sel_lines = { "(no original selection stored)" }
  end

  local separator = { "", "──── anchor lost; showing original selection ────", "" }
  local replacement = vim.list_extend({}, body_lines)
  vim.list_extend(replacement, separator)
  vim.list_extend(replacement, sel_lines)

  if ctx.preview and ctx.preview.set_lines then
    pcall(function()
      ctx.preview:set_lines(replacement)
    end)
  else
    pcall(function()
      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, replacement)
      vim.bo[ctx.buf].modifiable = false
    end)
  end
  if ctx.preview and ctx.preview.highlight then
    pcall(function()
      ctx.preview:highlight({ ft = "markdown" })
    end)
  else
    pcall(function()
      vim.bo[ctx.buf].filetype = "markdown"
    end)
  end

  vim.api.nvim_buf_clear_namespace(ctx.buf, ns, 0, -1)

  local sel_row0 = #body_lines + #separator
  for i, sl in ipairs(sel_lines) do
    pcall(vim.api.nvim_buf_set_extmark, ctx.buf, ns, sel_row0 + (i - 1), 0, {
      end_row = sel_row0 + (i - 1),
      end_col = #sl,
      hl_group = "SideNoteHighlight",
      hl_mode = "combine",
      priority = 200,
    })
  end

  if ctx.win and vim.api.nvim_win_is_valid(ctx.win) then
    pcall(vim.api.nvim_win_call, ctx.win, function()
      vim.cmd("normal! gg")
    end)
  end
end

local function snacks_picker(items, ctx)
  local ok, snacks = pcall(require, "snacks.picker")
  if not ok then
    return false
  end
  local picker_items = {}
  for i, it in ipairs(items) do
    local c = it.comment
    local row = (c.startLine or 0) + 1
    -- Use col=0 and skip end_pos: snacks's preview validates pos/end_pos against
    -- the loaded buffer's line length and crashes on out-of-range. Our own
    -- render_preview re-applies the SideNoteHighlight span with proper clamping.
    local entry = {
      idx = i,
      text = it.label,
      comment = c,
      pos = { row, 0 },
    }
    if ctx.file then
      entry.file = ctx.file
    end
    table.insert(picker_items, entry)
  end
  snacks.pick({
    title = "sidenote",
    items = picker_items,
    format = function(item)
      return { { item.text } }
    end,
    preview = function(pctx)
      local pok, perr = pcall(render_preview, pctx)
      if not pok then
        pcall(function()
          vim.bo[pctx.buf].modifiable = true
          vim.api.nvim_buf_set_lines(pctx.buf, 0, -1, false, {
            "(sidenote preview unavailable)",
            tostring(perr),
          })
          vim.bo[pctx.buf].modifiable = false
        end)
      end
    end,
    confirm = function(picker, item)
      picker:close()
      if item and ctx.on_pick then
        ctx.on_pick(item.comment)
      end
    end,
    actions = {
      delete_note = function(picker, item)
        picker:close()
        if item and ctx.on_delete then
          ctx.on_delete(item.comment)
        end
      end,
      toggle_resolved = function(picker, item)
        picker:close()
        if item and ctx.on_toggle_resolved then
          ctx.on_toggle_resolved(item.comment)
        end
      end,
      toggle_show_resolved = function(picker)
        picker:close()
        if ctx.on_toggle_show_resolved then
          ctx.on_toggle_show_resolved()
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-d>"] = { "delete_note", mode = { "n", "i" } },
          ["<C-r>"] = { "toggle_resolved", mode = { "n", "i" } },
          ["<C-x>"] = { "toggle_show_resolved", mode = { "n", "i" } },
        },
      },
    },
  })
  return true
end

local function telescope_picker(items, ctx)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return false
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "sidenote (CR jump | C-d delete | C-r resolve | C-x show-resolved)",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return {
            value = item.comment,
            display = item.label,
            ordinal = item.label,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry and ctx.on_pick then
            ctx.on_pick(entry.value)
          end
        end)
        map({ "n", "i" }, "<C-d>", function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry and ctx.on_delete then
            ctx.on_delete(entry.value)
          end
        end)
        map({ "n", "i" }, "<C-r>", function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry and ctx.on_toggle_resolved then
            ctx.on_toggle_resolved(entry.value)
          end
        end)
        map({ "n", "i" }, "<C-x>", function()
          actions.close(prompt_bufnr)
          if ctx.on_toggle_show_resolved then
            ctx.on_toggle_show_resolved()
          end
        end)
        return true
      end,
    })
    :find()
  return true
end

local function fzf_picker(items, ctx)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    return false
  end
  local label_to_comment = {}
  local entries = {}
  for i, it in ipairs(items) do
    local key = string.format("%d\t%s", i, it.label)
    label_to_comment[key] = it.comment
    table.insert(entries, key)
  end
  local lookup = function(sel)
    if not sel or #sel == 0 then
      return nil
    end
    return label_to_comment[sel[1]]
  end
  fzf.fzf_exec(entries, {
    prompt = "sidenote> ",
    actions = {
      ["default"] = function(sel)
        local c = lookup(sel)
        if c and ctx.on_pick then
          ctx.on_pick(c)
        end
      end,
      ["ctrl-d"] = function(sel)
        local c = lookup(sel)
        if c and ctx.on_delete then
          ctx.on_delete(c)
        end
      end,
      ["ctrl-r"] = function(sel)
        local c = lookup(sel)
        if c and ctx.on_toggle_resolved then
          ctx.on_toggle_resolved(c)
        end
      end,
      ["ctrl-x"] = function()
        if ctx.on_toggle_show_resolved then
          ctx.on_toggle_show_resolved()
        end
      end,
    },
  })
  return true
end

function M.open(comments, ctx)
  ctx = ctx or {}
  local show_resolved = ctx.show_resolved == true
  local sort_order = ctx.sort_order or "position"
  local items = build_items(comments, show_resolved, ctx.body_for)
  sort_items(items, sort_order)

  if #items == 0 then
    if #comments == 0 then
      vim.notify("No sidenotes for this file", vim.log.levels.INFO, { title = "sidenote" })
      return
    end
    local hidden = 0
    for _, c in ipairs(comments) do
      if c.resolved == true then
        hidden = hidden + 1
      end
    end
    local show_label = string.format("Show %d resolved note%s", hidden, hidden == 1 and "" or "s")
    local prompt = string.format("sidenote: %d note%s hidden by filter", hidden, hidden == 1 and "" or "s")
    vim.ui.select({ show_label, "Cancel" }, {
      prompt = prompt,
    }, function(choice)
      if choice == show_label and ctx.on_toggle_show_resolved then
        ctx.on_toggle_show_resolved()
      end
    end)
    return
  end

  if snacks_picker(items, ctx) then
    return
  end
  if telescope_picker(items, ctx) then
    return
  end
  if fzf_picker(items, ctx) then
    return
  end
  fallback_select(items, ctx.on_pick)
end

return M
