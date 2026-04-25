local M = {}

local uv = vim.uv or vim.loop

local TOP_LEVEL_ORDER = {
  "commentSortOrder",
  "showHighlights",
  "markdownFolder",
  "highlightColor",
  "highlightOpacity",
  "showResolvedComments",
  "comments",
}

local COMMENT_FIELD_ORDER = {
  "id",
  "filePath",
  "startLine",
  "startChar",
  "endLine",
  "endChar",
  "selectedText",
  "selectedTextHash",
  "comment",
  "timestamp",
  "isOrphaned",
  "commentPath",
  "resolved",
  "resolvedAt",
}

local function read_file(path)
  local fd = uv.fs_open(path, "r", 420)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil
  end
  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return data
end

local function write_atomic(path, contents)
  local tmp = path .. ".tmp"
  local fd, err = uv.fs_open(tmp, "w", 420)
  if not fd then
    error("sidenote.storage: failed to open " .. tmp .. ": " .. tostring(err))
  end
  local ok, write_err = pcall(uv.fs_write, fd, contents, 0)
  uv.fs_close(fd)
  if not ok then
    pcall(uv.fs_unlink, tmp)
    error("sidenote.storage: write failed: " .. tostring(write_err))
  end
  local rok, rerr = uv.fs_rename(tmp, path)
  if not rok then
    pcall(uv.fs_unlink, tmp)
    error("sidenote.storage: rename failed: " .. tostring(rerr))
  end
end

local function escape_string(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\b", "\\b")
  s = s:gsub("\f", "\\f")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  s = s:gsub("[%z\1-\31]", function(c)
    return string.format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

local function is_array(t)
  if type(t) ~= "table" then
    return false
  end
  if vim.islist then
    return vim.islist(t)
  end
  return vim.tbl_islist(t)
end

local function ordered_keys(t, preferred)
  local seen = {}
  local out = {}
  preferred = preferred or {}
  for _, k in ipairs(preferred) do
    if t[k] ~= nil then
      table.insert(out, k)
      seen[k] = true
    end
  end
  local extra = {}
  for k, _ in pairs(t) do
    if not seen[k] then
      table.insert(extra, k)
    end
  end
  table.sort(extra)
  for _, k in ipairs(extra) do
    table.insert(out, k)
  end
  return out
end

local encode_value

local function encode_table(t, indent_level, key_order)
  local indent = string.rep("  ", indent_level)
  local child_indent = string.rep("  ", indent_level + 1)
  if is_array(t) then
    if #t == 0 then
      return "[]"
    end
    local parts = { "[" }
    for i, v in ipairs(t) do
      local rendered = encode_value(v, indent_level + 1)
      if i < #t then
        table.insert(parts, child_indent .. rendered .. ",")
      else
        table.insert(parts, child_indent .. rendered)
      end
    end
    table.insert(parts, indent .. "]")
    return table.concat(parts, "\n")
  end
  local keys = ordered_keys(t, key_order)
  if #keys == 0 then
    return "{}"
  end
  local parts = { "{" }
  for i, k in ipairs(keys) do
    local v = t[k]
    local rendered = encode_value(v, indent_level + 1)
    local sep = (i < #keys) and "," or ""
    table.insert(parts, child_indent .. escape_string(k) .. ": " .. rendered .. sep)
  end
  table.insert(parts, indent .. "}")
  return table.concat(parts, "\n")
end

encode_value = function(v, indent_level)
  local t = type(v)
  if v == vim.NIL then
    return "null"
  end
  if t == "nil" then
    return "null"
  end
  if t == "boolean" then
    return v and "true" or "false"
  end
  if t == "number" then
    if v ~= v then
      return "null"
    end
    if v == math.huge or v == -math.huge then
      return "null"
    end
    if v == math.floor(v) and math.abs(v) < 1e16 then
      return string.format("%d", v)
    end
    return tostring(v)
  end
  if t == "string" then
    return escape_string(v)
  end
  if t == "table" then
    if is_array(v) then
      return encode_table(v, indent_level, nil)
    end
    local key_order = nil
    if indent_level == 0 then
      key_order = TOP_LEVEL_ORDER
    end
    if v.id ~= nil and v.filePath ~= nil and v.startLine ~= nil then
      key_order = COMMENT_FIELD_ORDER
    end
    return encode_table(v, indent_level, key_order)
  end
  return "null"
end

function M.encode(data)
  return encode_value(data, 0) .. "\n"
end

function M.load(path)
  local raw = read_file(path)
  if not raw then
    local defaults = require("sidenote.vault").default_settings()
    return defaults
  end
  local ok, decoded = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  if not ok then
    error("sidenote.storage: failed to decode " .. path .. ": " .. tostring(decoded))
  end
  if type(decoded) ~= "table" then
    error("sidenote.storage: expected JSON object at " .. path)
  end
  if decoded.comments == nil then
    decoded.comments = {}
  end
  return decoded
end

function M.save(path, data)
  local encoded = M.encode(data)
  write_atomic(path, encoded)
end

function M.update(path, mutator)
  local current = M.load(path)
  local result = mutator(current)
  local to_save = result or current
  M.save(path, to_save)
  return to_save
end

return M
