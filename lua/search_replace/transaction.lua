local engine = require("search_replace.engine")
local M = {}

local function buffer_for(filename)
  local bufnr = vim.fn.bufnr(filename)
  if bufnr < 0 then bufnr = vim.fn.bufadd(filename) end
  if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
  return bufnr
end

local function later(a, b)
  return a.lnum > b.lnum or (a.lnum == b.lnum and a.start_byte > b.start_byte)
end

function M.targets(all, selected)
  return #selected > 0 and selected or all
end

function M.plan(matches, pattern, replacement, global)
  local operations, failures = {}, {}
  local seen = {}
  for _, match in ipairs(matches) do
    local key = table.concat({ match.filename, match.lnum, match.original_text }, "\0")
    if not global or not seen[key] then
      seen[key] = true
      local ok, bufnr = pcall(buffer_for, match.filename)
      if not ok then
        failures[#failures + 1] = { match = match, error = tostring(bufnr) }
      else
        local line = vim.api.nvim_buf_get_lines(bufnr, match.lnum - 1, match.lnum, true)[1]
        local computed, err = line and engine.compute(pattern, replacement, match, line, global)
        if not computed then
          failures[#failures + 1] = { match = match, error = err or "missing line" }
        else
          computed.bufnr, computed.filename, computed.lnum = bufnr, match.filename, match.lnum
          operations[#operations + 1] = computed
        end
      end
    end
  end
  table.sort(operations, function(a, b)
    return a.filename == b.filename and later(a, b) or a.filename < b.filename
  end)
  for i = 2, #operations do
    local a, b = operations[i - 1], operations[i]
    if a.filename == b.filename and a.lnum == b.lnum then
      local overlap = b.end_byte > a.start_byte
        or (a.start_byte == a.end_byte and b.start_byte == b.end_byte and a.start_byte == b.start_byte)
      if overlap then return nil, "overlapping replacement ranges" end
    end
  end
  return operations, failures
end

function M.apply(operations)
  local changed, applied, failed = {}, 0, 0
  for _, op in ipairs(operations) do
    if changed[op.bufnr] then
      vim.api.nvim_buf_call(op.bufnr, function() pcall(vim.cmd, "undojoin") end)
    end
    local replacement = op.new_text:gsub("\n", "\0")
    local ok = pcall(
      vim.api.nvim_buf_set_text,
      op.bufnr, op.lnum - 1, op.start_byte, op.lnum - 1, op.end_byte,
      vim.split(replacement, "\r", { plain = true })
    )
    if ok then
      applied, changed[op.bufnr] = applied + 1, true
    else
      failed = failed + 1
    end
  end
  return applied, failed
end

function M.run(matches, pattern, replacement, global)
  local operations, failures = M.plan(matches, pattern, replacement, global)
  if not operations then return { applied = 0, stale = 0, failed = #matches, error = failures } end
  local applied, failed = M.apply(operations)
  return { applied = applied, stale = #failures, failed = failed, details = failures }
end

return M
