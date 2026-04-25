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

-- Build a contiguous joined string from `lines[from_idx + 1 .. to_idx + 1]`
-- (0-indexed `from_idx`/`to_idx` for callers' convenience). Also returns a
-- `line_starts` array where `line_starts[k]` is the 1-indexed byte offset of
-- the k-th line's start within the joined string. Lines are joined with `\n`.
local function build_joined(lines, from_idx, to_idx)
  local pieces = {}
  local line_starts = {}
  local offset = 1 -- 1-indexed byte offset
  for i = from_idx, to_idx do
    table.insert(line_starts, offset)
    local lt = lines[i + 1] or ""
    table.insert(pieces, lt)
    offset = offset + #lt + 1 -- + 1 for the joining "\n"
  end
  -- Lines joined by '\n' (no trailing newline). offset_to_line_col uses bisect
  -- on line_starts; offsets at end-of-string map to the last line's exclusive
  -- end column.
  local joined = table.concat(pieces, "\n")
  return joined, line_starts
end

-- bisect_right: largest index k such that line_starts[k] <= offset.
local function locate_offset(line_starts, offset)
  -- Binary search for the rightmost line_starts[k] <= offset.
  local lo, hi = 1, #line_starts
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if line_starts[mid] <= offset then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo
end

-- Convert a 1-indexed byte offset within a joined string back to (line_idx, col)
-- where `line_idx` is the absolute 0-indexed line in the original `lines` table
-- (caller supplies `from_idx` so we know the absolute base) and `col` is the
-- 0-indexed byte column within that line.
local function offset_to_line_col(line_starts, offset, from_idx)
  local k = locate_offset(line_starts, offset)
  local col = offset - line_starts[k]
  return from_idx + (k - 1), col
end

local function find_all_plain(haystack, needle)
  local positions = {}
  if needle == "" then
    return positions
  end
  local start = 1
  while true do
    local s, e = string.find(haystack, needle, start, true)
    if not s then
      break
    end
    table.insert(positions, { start_byte = s, end_byte = e })
    start = s + 1
  end
  return positions
end

local function stage1_neighborhood_multiline(lines, comment, needle, hash)
  local total = #lines
  local needle_lines = 1 + select(2, needle:gsub("\n", "\n"))
  local from = math.max(0, comment.startLine - 10)
  local to = math.min(total - 1, (comment.endLine or comment.startLine) + needle_lines + 10)
  if to < from then
    return nil
  end
  local joined, line_starts = build_joined(lines, from, to)
  local positions = find_all_plain(joined, needle)
  local best = nil
  for _, pos in ipairs(positions) do
    local snippet = string.sub(joined, pos.start_byte, pos.end_byte)
    if sha256(snippet) == hash then
      local sline, scol = offset_to_line_col(line_starts, pos.start_byte, from)
      -- end_byte is inclusive in find()'s return; converting offset+1 gives the
      -- exclusive end position for our (line, col) pair.
      local eline, ecol = offset_to_line_col(line_starts, pos.end_byte + 1, from)
      local d = distance(sline, scol, comment.startLine, comment.startChar or 0)
      if best == nil or d < best.distance then
        best = {
          startLine = sline,
          startChar = scol,
          endLine = eline,
          endChar = ecol,
          selectedText = snippet,
          distance = d,
        }
      end
    end
  end
  return best
end

local function stage1_neighborhood(lines, comment)
  local needle = comment.selectedText
  local hash = comment.selectedTextHash
  if not needle or needle == "" or not hash then
    return nil
  end
  if string.find(needle, "\n", 1, true) then
    return stage1_neighborhood_multiline(lines, comment, needle, hash)
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

local function stage2_full_scan_multiline(lines, comment, needle, hash)
  if #lines == 0 then
    return nil
  end
  local joined, line_starts = build_joined(lines, 0, #lines - 1)
  local joined_len = #joined
  local base_len = #needle

  local best = nil
  local match_with_length = function(window_len)
    if window_len > joined_len then
      return
    end
    for start = 1, joined_len - window_len + 1 do
      local snippet = string.sub(joined, start, start + window_len - 1)
      if sha256(snippet) == hash then
        local sline, scol = offset_to_line_col(line_starts, start, 0)
        local eline, ecol = offset_to_line_col(line_starts, start + window_len, 0)
        local d = distance(sline, scol, comment.startLine, comment.startChar or 0)
        if best == nil or d < best.distance then
          best = {
            startLine = sline,
            startChar = scol,
            endLine = eline,
            endChar = ecol,
            selectedText = snippet,
            distance = d,
          }
        end
      end
    end
  end

  match_with_length(base_len)
  return best
end

local function stage2_full_scan(lines, comment)
  local needle = comment.selectedText
  local hash = comment.selectedTextHash
  if not needle or needle == "" or not hash then
    return nil
  end
  if string.find(needle, "\n", 1, true) then
    return stage2_full_scan_multiline(lines, comment, needle, hash)
  end
  local base_len = #needle

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

  match_with_length(base_len)
  return best
end

local function stage3_regex(lines, comment)
  local needle = comment.selectedText
  if not needle or needle == "" then
    return nil
  end
  if string.find(needle, "\n", 1, true) then
    if #lines == 0 then
      return nil
    end
    local joined, line_starts = build_joined(lines, 0, #lines - 1)
    local s, e = string.find(joined, needle, 1, true)
    if not s then
      return nil
    end
    local sline, scol = offset_to_line_col(line_starts, s, 0)
    local eline, ecol = offset_to_line_col(line_starts, e + 1, 0)
    return {
      startLine = sline,
      startChar = scol,
      endLine = eline,
      endChar = ecol,
      selectedText = needle,
    }
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
  if comment.endLine ~= match.endLine then
    comment.endLine = match.endLine
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
