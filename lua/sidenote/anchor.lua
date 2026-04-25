local M = {}

local function sha256(s)
  return vim.fn.sha256(s)
end

local function get_buffer_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function distance(line, col, ref_line, ref_col)
  local ld = math.abs(line - ref_line)
  local cd = math.abs(col - ref_col)
  return ld * 1000 + cd
end

local function find_in_line(line_text, needle)
  local positions = {}
  if needle == "" then
    return positions
  end
  local start = 1
  while true do
    local s, e = string.find(line_text, needle, start, true)
    if not s then
      break
    end
    table.insert(positions, { start_col = s - 1, end_col = e })
    start = s + 1
  end
  return positions
end

local function utf8_safe_substring(line, start_byte, length)
  if start_byte < 0 then
    return nil
  end
  if start_byte + length > #line then
    return nil
  end
  return string.sub(line, start_byte + 1, start_byte + length)
end

local function stage1_neighborhood(lines, comment)
  local needle = comment.selectedText
  local hash = comment.selectedTextHash
  if not needle or needle == "" or not hash then
    return nil
  end
  local total = #lines
  local from = math.max(0, comment.startLine - 10)
  local to = math.min(total - 1, (comment.endLine or comment.startLine) + 10)
  local best = nil
  for line_idx = from, to do
    local line_text = lines[line_idx + 1] or ""
    local positions = find_in_line(line_text, needle)
    for _, pos in ipairs(positions) do
      local snippet = string.sub(line_text, pos.start_col + 1, pos.end_col)
      if sha256(snippet) == hash then
        local d = distance(line_idx, pos.start_col, comment.startLine, comment.startChar)
        if best == nil or d < best.distance then
          best = {
            startLine = line_idx,
            startChar = pos.start_col,
            endLine = line_idx,
            endChar = pos.end_col,
            selectedText = snippet,
            distance = d,
          }
        end
      end
    end
  end
  return best
end

local function stage2_full_scan(lines, comment)
  local needle = comment.selectedText
  local hash = comment.selectedTextHash
  if not needle or needle == "" or not hash then
    return nil
  end
  local base_len = #needle
  local lengths = { base_len }
  local lo = math.floor(0.8 * base_len)
  local hi = math.ceil(1.2 * base_len)
  if lo < 1 then
    lo = 1
  end
  for n = lo, hi do
    if n ~= base_len then
      table.insert(lengths, n)
    end
  end

  local best = nil
  local match_with_length = function(window_len)
    for line_idx = 0, #lines - 1 do
      local line_text = lines[line_idx + 1] or ""
      if #line_text >= window_len then
        for start_col = 0, #line_text - window_len do
          local snippet = utf8_safe_substring(line_text, start_col, window_len)
          if snippet and sha256(snippet) == hash then
            local d = distance(line_idx, start_col, comment.startLine, comment.startChar)
            if best == nil or d < best.distance then
              best = {
                startLine = line_idx,
                startChar = start_col,
                endLine = line_idx,
                endChar = start_col + window_len,
                selectedText = snippet,
                distance = d,
              }
            end
          end
        end
      end
    end
  end

  for _, n in ipairs(lengths) do
    match_with_length(n)
    if best ~= nil and n == base_len then
      return best
    end
  end
  return best
end

local function stage3_regex(lines, comment)
  local needle = comment.selectedText
  if not needle or needle == "" then
    return nil
  end
  for line_idx = 0, #lines - 1 do
    local line_text = lines[line_idx + 1] or ""
    local positions = find_in_line(line_text, needle)
    if #positions > 0 then
      local pos = positions[1]
      return {
        startLine = line_idx,
        startChar = pos.start_col,
        endLine = line_idx,
        endChar = pos.end_col,
        selectedText = needle,
      }
    end
  end
  return nil
end

function M.sha256(s)
  return sha256(s)
end

-- Stage 1 only: neighborhood ±10 lines + hash verify. Cheap; safe in UI hot
-- paths (preview, hover) where Stage 2's full-file scan would freeze the editor.
function M.resolve_neighborhood(lines, comment)
  if comment.selectedTextHash and comment.selectedTextHash ~= "" then
    return stage1_neighborhood(lines, comment), "stage1"
  end
  return nil, "no-hash"
end

function M.resolve(lines, comment)
  if comment.selectedTextHash and comment.selectedTextHash ~= "" then
    local s1 = stage1_neighborhood(lines, comment)
    if s1 then
      return s1, "stage1"
    end
    local s2 = stage2_full_scan(lines, comment)
    if s2 then
      return s2, "stage2"
    end
    return nil, "orphaned"
  end
  local s3 = stage3_regex(lines, comment)
  if s3 then
    return s3, "stage3"
  end
  return nil, "orphaned"
end

function M.apply_resolution(comment, match)
  if match == nil then
    comment.isOrphaned = true
    return comment, true
  end
  local changed = false
  if comment.startLine ~= match.startLine then
    comment.startLine = match.startLine
    changed = true
  end
  if comment.startChar ~= match.startChar then
    comment.startChar = match.startChar
    changed = true
  end
  if comment.endLine ~= match.startLine then
    comment.endLine = match.startLine
    changed = true
  end
  if comment.endChar ~= match.endChar then
    comment.endChar = match.endChar
    changed = true
  end
  if comment.selectedText ~= match.selectedText then
    comment.selectedText = match.selectedText
    changed = true
  end
  if comment.isOrphaned == true then
    comment.isOrphaned = false
    changed = true
  end
  return comment, changed
end

function M.resolve_buffer(bufnr, comments)
  local lines = get_buffer_lines(bufnr)
  local any_changed = false
  for _, comment in ipairs(comments) do
    local match = M.resolve(lines, comment)
    local _, changed = M.apply_resolution(comment, match)
    if changed then
      any_changed = true
    end
  end
  return any_changed
end

return M
