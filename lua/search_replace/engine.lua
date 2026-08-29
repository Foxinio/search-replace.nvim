local M = {}

local function regex_error(pattern)
  local ok, err = pcall(vim.regex, pattern)
  if ok then return nil end
  return tostring(err):gsub("^.-: ", "")
end

function M.find_matches(pattern, line)
  if pattern == "" then return {} end
  local err = regex_error(pattern)
  if err then return nil, err end
  local out, start = {}, 0
  while true do
    local ok, match = pcall(vim.fn.matchstrpos, line, pattern, start)
    if not ok then return nil, tostring(match) end
    local start_byte, end_byte = match[2], match[3]
    if start_byte < 0 then break end
    out[#out + 1] = {
      start_byte = start_byte,
      end_byte = end_byte,
      matched_text = line:sub(start_byte + 1, end_byte),
    }
    if end_byte > start then
      start = end_byte
    elseif end_byte == #line then
      break
    else
      start = vim.fn.byteidx(line, vim.fn.charidx(line, end_byte) + 1)
    end
  end
  return out
end

local function byte_columns(line, last)
  local columns, byte = {}, 0
  while byte <= last do
    columns[#columns + 1] = byte
    if byte == #line then break end
    byte = vim.fn.byteidx(line, vim.fn.charidx(line, byte) + 1)
  end
  return columns
end

local function at_column(pattern, column)
  local offset, mode = 1, "m"
  if pattern:sub(offset, offset + 4):match([[^\%%#=[012]$]]) then offset = offset + 5 end
  local engine_end = offset
  while true do
    local modifier = pattern:sub(offset, offset + 1)
    if modifier == [[\c]] or modifier == [[\C]] then
      offset = offset + 2
    elseif modifier == [[\v]] or modifier == [[\m]] or modifier == [[\M]] or modifier == [[\V]] then
      mode, offset = modifier:sub(2), offset + 2
    else
      break
    end
  end
  if mode == "v" or mode == "V" then offset = engine_end end
  -- In default/magic modes a leading ^ must remain at the start of the pattern.
  if mode ~= "V" and pattern:sub(offset, offset) == "^" then offset = offset + 1 end
  return pattern:sub(1, offset - 1) .. ([[\%%%dc]]):format(column) .. pattern:sub(offset)
end

-- Native substitute is the single source of truth for preview and application.
function M.compute(pattern, replacement, occurrence, line, global)
  if line ~= occurrence.original_text then return nil, "stale line" end
  local anchored
  for _, raw_start in ipairs(byte_columns(line, occurrence.start_byte)) do
    local candidate = at_column(pattern, raw_start + 1)
    local ok, match = pcall(vim.fn.matchstrpos, line, candidate)
    if ok and match[2] == occurrence.start_byte and match[3] == occurrence.end_byte then
      anchored = candidate
      break
    end
  end
  if not anchored then return nil, "stale match" end
  local ok, new_line = pcall(vim.fn.substitute, line, global and pattern or anchored, replacement, global and "g" or "")
  if not ok then return nil, tostring(new_line) end
  if global then
    return { start_byte = 0, end_byte = #line, old_text = line, new_text = new_line, old_line = line, new_line = new_line }
  end
  local suffix_len = #line - occurrence.end_byte
  return {
    start_byte = occurrence.start_byte,
    end_byte = occurrence.end_byte,
    old_text = occurrence.matched_text,
    new_text = new_line:sub(occurrence.start_byte + 1, #new_line - suffix_len),
    old_line = line,
    new_line = new_line,
  }
end

return M
