local M = {}

local function valid_delimiter(char)
  return #char == 1 and not char:match("[%w\\\"|]")
end

local function segment(text, delimiter, start)
  local out, slashes = {}, 0
  for index = start, #text do
    local char = text:sub(index, index)
    if char == delimiter then
      if slashes % 2 == 0 then return table.concat(out), index + 1 end
      out[#out] = nil
    end
    out[#out + 1] = char
    slashes = char == "\\" and slashes + 1 or 0
  end
  return table.concat(out)
end

function M.parse(text)
  local state = { pattern = "", replacement = nil, flags = { global = false }, mode = "idle", parse_error = nil }
  if text == "" then return state end
  local delimiter = text:sub(1, 1)
  if not valid_delimiter(delimiter) then
    state.parse_error = "invalid delimiter"
    return state
  end
  state.mode = "search"
  local pattern, next_index = segment(text, delimiter, 2)
  state.pattern = pattern
  if not next_index then return state end
  state.mode = "replace"
  state.replacement, next_index = segment(text, delimiter, next_index)
  if state.replacement:sub(1, 2) == [[\=]] then
    state.parse_error = [[\= replacement expressions are not supported]]
  end
  if next_index then
    local flags = text:sub(next_index)
    if flags == "g" then state.flags.global = true
    elseif flags ~= "" then state.parse_error = "only the g flag is supported" end
  end
  return state
end

function M.attach(prompt_bufnr, state, changed)
  local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
  local function sync()
    if not vim.api.nvim_buf_is_valid(prompt_bufnr) then return end
    local parsed = M.parse(picker:_get_prompt())
    local pattern_changed = parsed.pattern ~= state.pattern
    local preview_changed = pattern_changed
      or parsed.replacement ~= state.replacement
      or parsed.mode ~= state.mode
      or parsed.flags.global ~= state.flags.global
      or parsed.parse_error ~= state.parse_error
    for key, value in pairs(parsed) do state[key] = value end
    if preview_changed then changed(pattern_changed) end
  end
  vim.api.nvim_buf_attach(prompt_bufnr, false, { on_lines = function() vim.schedule(sync) end })
  sync()
end

return M
