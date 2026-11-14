vim.o.columns = 160
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "before", "foo foo", "after" }, root .. "/a.txt")
local discover = root .. "/discover"
vim.fn.writefile({ "#!/bin/sh", "printf 'a.txt\\n'" }, discover)
vim.fn.setfperm(discover, "rwx------")
require("search_replace").setup({
  search = { debounce = 0, max_results = 1, command = { discover } },
  mappings = { i = { replace_current = "<C-E>", toggle_selection = "<C-T>", replace_selected_or_all = "<C-B>" } },
})
require("search_replace").open({ cwd = root })

local telescope_state = require("telescope.state")
local prompt_bufnr = telescope_state.get_existing_prompt_bufnrs()[1]
local status = telescope_state.get_status(prompt_bufnr)
local picker = status.picker
local function wait_for(check, message)
  assert(vim.wait(3000, check, 10), message)
end
local function preview()
  local bufnr = picker.previewer and picker.previewer.state and picker.previewer.state.bufnr
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then return "" end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, true)
  return ok and table.concat(lines, "\n") or ""
end
local function preview_cursor()
  return vim.api.nvim_win_get_cursor(picker.previewer.state.winid)[1]
end

wait_for(function() return type(picker.manager) == "table" end, "picker initialization")
wait_for(function()
  local text = preview()
  return text:find("<C-E>  Replace current occurrence", 1, true)
    and text:find("<C-T>  Toggle selection", 1, true)
    and text:find("<C-B>  Replace selected occurrences", 1, true)
end, "idle instructions")
picker:set_prompt("invalid")
wait_for(function() return preview():find("invalid delimiter", 1, true) end, "invalid delimiter")
picker:set_prompt("/foo")
wait_for(function()
  return type(picker.manager) == "table" and picker.manager:num_results() == 1 and preview():find(" 2 foo foo", 1, true)
end, "source preview")
wait_for(function() return preview_cursor() == 2 end, "source preview cursor")
picker:set_prompt("/foo/bar")
wait_for(function()
  local text = preview()
  return text:find(" 1 before", 1, true)
    and text:find("+2 bar foo", 1, true)
    and text:find(" 3 after", 1, true)
end, "whole-file single-occurrence diff")
wait_for(function() return preview_cursor() == 2 end, "replacement preview cursor")
picker:set_prompt("/foo/bar/g")
wait_for(function() return preview():find("+2 bar bar", 1, true) end, "global diff")

require("telescope.actions").close(prompt_bufnr)
require("telescope.builtin").resume()
prompt_bufnr = telescope_state.get_existing_prompt_bufnrs()[1]
status = telescope_state.get_status(prompt_bufnr)
assert(status.layout and status.picker.manager:num_results() == 1)
require("telescope.actions").close(prompt_bufnr)
vim.fn.writefile({ "foo", "foo", "foo", "foo" }, root .. "/a.txt")
require("search_replace.config").values.search.max_results = 10
require("search_replace").open({ cwd = root })
prompt_bufnr = telescope_state.get_existing_prompt_bufnrs()[1]
picker = telescope_state.get_status(prompt_bufnr).picker
picker:set_prompt("/foo/bar")
wait_for(function() return picker.manager and picker.manager:num_results() == 4 end, "replacement results")
picker:set_selection(picker:get_row(2))
local row = picker:get_selection_row()
local replace = vim.api.nvim_buf_call(prompt_bufnr, function()
  return vim.fn.maparg("<C-E>", "i", false, true).callback
end)
replace()
wait_for(function() return picker.manager:num_results() == 3 end, "replacement refresh")
assert(picker:get_selection_row() == row, "replacement moved selection")
picker:set_prompt("/foo")
wait_for(function() return preview():find(" 3 foo", 1, true) end, "return to search preview")
require("telescope.actions").close(prompt_bufnr)

-- Editing settings follows editable-telescope's close/input/reopen flow.
require("search_replace").setup({ search = { debounce = 0, args = { "-t", "lua" }, globs = { "*.missing" } } })
vim.fn.writefile({ "foo" }, root .. "/a.lua")
vim.fn.mkdir(root .. "/nested", "p")
vim.fn.writefile({ "foo foo" }, root .. "/nested/b.lua")
require("search_replace").open({ cwd = root, search = { args = {}, globs = {} } })
local function current()
  prompt_bufnr = telescope_state.get_existing_prompt_bufnrs()[1]
  picker = telescope_state.get_status(prompt_bufnr).picker
end
current()
picker:set_prompt("/foo/bar/g")
wait_for(function() return picker.manager and picker.manager:num_results() == 6 end, "per-picker list overrides")
for _, mode in ipairs({ "i", "n" }) do
  vim.api.nvim_buf_call(prompt_bufnr, function()
    assert(vim.fn.maparg("<C-s>", mode, false, true).buffer == 1)
    assert(vim.fn.maparg("<C-a>", mode, false, true).buffer == 1)
  end)
end
local original_input = vim.ui.input
local function edit(key, answer, check_options)
  local previous = prompt_bufnr
  vim.ui.input = function(options, callback)
    if check_options then check_options(options) end
    callback(answer)
  end
  local callback = vim.api.nvim_buf_call(prompt_bufnr, function()
    return vim.fn.maparg(key, "i", false, true).callback
  end)
  callback()
  wait_for(function()
    local buffers = telescope_state.get_existing_prompt_bufnrs()
    return buffers[1] and buffers[1] ~= previous
  end, "settings picker reopened")
  current()
  assert(picker:_get_prompt() == "/foo/bar/g", "settings lost prompt")
end
edit("<C-a>", [[-g '*.lua' -g '!nested/**']])
wait_for(function() return picker.manager and picker.manager:num_results() == 1 end, "edited glob")
assert(#picker:get_multi_selection() == 0)
edit("<C-a>", nil, function(options) assert(options.default == [[-g '*.lua' -g '!nested/**']]) end)
wait_for(function() return picker.manager and picker.manager:num_results() == 1 end, "canceled flags")
edit("<C-a>", "--json")
wait_for(function() return preview():find("unsupported rg argument: --json", 1, true) end, "flag error preview")
assert(not picker:get_selection().value.filename, "invalid flags retained matches")
edit("<C-a>", "-g '*.lua'", function(options) assert(options.default == "--json") end)
wait_for(function() return picker.manager and picker.manager:num_results() == 3 end, "corrected flags")
edit("<C-s>", root .. "/nested", function(options) assert(options.completion == "dir") end)
wait_for(function() return picker.manager and picker.manager:num_results() == 2 end, "changed root")
assert(vim.fs.normalize(picker.cwd) == root .. "/nested")
edit("<C-s>", nil)
assert(vim.fs.normalize(picker.cwd) == root .. "/nested")
edit("<C-s>", root .. "/does-not-exist")
assert(vim.fs.normalize(picker.cwd) == root .. "/nested")
require("telescope.actions").close(prompt_bufnr)
require("search_replace").open({ cwd = root, search = { args = {}, globs = {}, command = { discover } } })
current()
picker:set_prompt("/foo/bar/g")
wait_for(function() return picker.manager and picker.manager:num_results() == 3 end, "custom discovery")
edit("<C-a>", "--hidden")
wait_for(function() return preview():find("custom discovery command", 1, true) end, "custom command flag error")
edit("<C-a>", "")
wait_for(function() return picker.manager and picker.manager:num_results() == 3 end, "clear custom command flag error")
require("telescope.actions").close(prompt_bufnr)
require("search_replace").open({ cwd = root, search = { args = { "--json" } } })
current()
wait_for(function() return preview():find("unsupported rg argument", 1, true) end, "idle flag error preview")
require("telescope.actions").close(prompt_bufnr)
local project = require("search_replace.project")
local original_search, last_state = project.search
project.search = function(state, ...)
  last_state = state
  return original_search(state, ...)
end
local slow_discover = root .. "/slow-discover"
vim.fn.writefile({ "#!/bin/sh", "sleep 0.2", "printf 'a.lua\\n'" }, slow_discover)
vim.fn.setfperm(slow_discover, "rwx------")
require("search_replace").open({ cwd = root, search = { args = {}, globs = {}, command = { slow_discover } } })
current()
picker:set_prompt("/foo/bar/g")
wait_for(function() return last_state and last_state.discovery_pending end, "pending discovery")
local previous_state = last_state
edit("<C-s>", root .. "/nested")
assert(not previous_state.discovery_pending and not previous_state.discovery_waiter, "closed picker did not cancel discovery")
wait_for(function() return last_state ~= previous_state and last_state.discovered end, "new root discovery")
assert(#last_state.matches == 0, "old root results survived reopening")
require("telescope.actions").close(prompt_bufnr)
project.search = original_search
vim.ui.input = original_input
print("telescope smoke test passed")
vim.cmd("qa!")
