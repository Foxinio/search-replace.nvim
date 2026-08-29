local M = {}
local separator = "  │  "

local function raw(picker)
  return picker:_get_prompt()
end

local function set_raw(picker, state)
  state.prompt_changing = true
  picker:set_prompt(state.search_pattern .. separator .. state.replacement)
  vim.schedule(function() state.prompt_changing = false end)
end

function M.attach(prompt_bufnr, state, changed)
  local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
  local prefix = picker.prompt_prefix

  local function sync()
    if state.prompt_changing or not vim.api.nvim_buf_is_valid(prompt_bufnr) then return end
    local text = raw(picker)
    local split = text:find(separator, 1, true)
    if not split then return set_raw(picker, state) end
    local search, replacement = text:sub(1, split - 1), text:sub(split + #separator)
    local search_changed = search ~= state.search_pattern
    local replacement_changed = replacement ~= state.replacement
    state.search_pattern, state.replacement = search, replacement
    if search_changed or replacement_changed then changed(search_changed, replacement_changed) end
  end

  vim.api.nvim_buf_attach(prompt_bufnr, false, {
    on_lines = function()
      vim.schedule(sync)
    end,
  })

  local function position()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local boundary = #prefix + #state.search_pattern
    return col, boundary, boundary + #separator
  end
  local function move(col)
    vim.api.nvim_win_set_cursor(0, { 1, col })
  end

  vim.keymap.set("i", "<Right>", function()
    local col, boundary = position()
    if col >= boundary and col < boundary + #separator then
      move(boundary + #separator)
      return ""
    else
      return "<Right>"
    end
  end, { buffer = prompt_bufnr, expr = true })
  vim.keymap.set("i", "<Left>", function()
    local col, boundary, replacement = position()
    if col > boundary and col <= replacement then
      move(boundary)
      return ""
    else
      return "<Left>"
    end
  end, { buffer = prompt_bufnr, expr = true })
  vim.keymap.set("i", "<BS>", function()
    local col, boundary, replacement = position()
    if col > boundary and col <= replacement then return "" end
    return "<BS>"
  end, { buffer = prompt_bufnr, expr = true })
  vim.keymap.set("i", "<Del>", function()
    local col, boundary, replacement = position()
    if col >= boundary and col < replacement then return "" end
    return "<Del>"
  end, { buffer = prompt_bufnr, expr = true })
  vim.keymap.set("i", "<Home>", function()
    local col, boundary, replacement = position()
    move(col >= replacement and replacement or #prefix)
  end, { buffer = prompt_bufnr })
  vim.keymap.set("i", "<End>", function()
    local col, _, replacement = position()
    move(col >= replacement and #vim.api.nvim_get_current_line() or replacement - #separator)
  end, { buffer = prompt_bufnr })

  set_raw(picker, state)
end

return M
