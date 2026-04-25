local M = {}

local NS_NAME = "sidenote"
local HL_GROUP = "SideNoteHighlight"
local namespace = vim.api.nvim_create_namespace(NS_NAME)

local function parse_hex(color)
  if type(color) ~= "string" then
    return nil
  end
  local hex = color:gsub("^#", "")
  if #hex ~= 6 then
    return nil
  end
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)
  if not r or not g or not b then
    return nil
  end
  return r, g, b
end

local function int_to_hex(n)
  return string.format("#%06x", n)
end

local function rgb_to_int(r, g, b)
  return r * 65536 + g * 256 + b
end

local function get_normal_bg()
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  if not ok or type(hl) ~= "table" then
    return nil
  end
  if hl.bg == nil then
    return nil
  end
  local n = hl.bg
  local r = math.floor(n / 65536) % 256
  local g = math.floor(n / 256) % 256
  local b = n % 256
  return r, g, b
end

local function blend(fr, fg, fb, br, bg, bb, alpha)
  alpha = math.max(0.0, math.min(1.0, alpha or 0.2))
  local r = math.floor(fr * alpha + br * (1 - alpha) + 0.5)
  local g = math.floor(fg * alpha + bg * (1 - alpha) + 0.5)
  local b = math.floor(fb * alpha + bb * (1 - alpha) + 0.5)
  return r, g, b
end

function M.namespace()
  return namespace
end

function M.ensure_highlight(settings)
  settings = settings or {}
  local color = settings.highlightColor or "#FFC800"
  local opacity = settings.highlightOpacity or 0.2
  local fr, fg, fb = parse_hex(color)
  if not fr then
    fr, fg, fb = 255, 200, 0
  end
  if not vim.o.termguicolors then
    pcall(vim.api.nvim_set_hl, 0, HL_GROUP, { ctermbg = "Yellow" })
    return
  end
  local br, bg, bb = get_normal_bg()
  if not br then
    pcall(vim.api.nvim_set_hl, 0, HL_GROUP, { bg = int_to_hex(rgb_to_int(fr, fg, fb)) })
    return
  end
  local r, g, b = blend(fr, fg, fb, br, bg, bb, opacity)
  pcall(vim.api.nvim_set_hl, 0, HL_GROUP, { bg = int_to_hex(rgb_to_int(r, g, b)) })
end

function M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

function M.render(bufnr, comments, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  opts = opts or {}
  local show_resolved = opts.show_resolved == true
  M.clear(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, c in ipairs(comments or {}) do
    local hide = c.isOrphaned == true or (c.resolved == true and not show_resolved)
    if not hide then
      local line = c.startLine
      if line and line >= 0 and line < line_count then
        local end_line = c.startLine
        local start_col = math.max(0, c.startChar or 0)
        local end_col = math.max(start_col, c.endChar or start_col)
        pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, line, start_col, {
          end_row = end_line,
          end_col = end_col,
          hl_group = HL_GROUP,
          hl_mode = "combine",
          priority = 200,
        })
      end
    end
  end
end

return M
