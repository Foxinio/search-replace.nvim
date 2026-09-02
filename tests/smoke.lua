local data = vim.fn.stdpath("data") .. "/lazy/"
vim.opt.runtimepath:prepend(data .. "plenary.nvim")
vim.opt.runtimepath:prepend(data .. "telescope.nvim")

require("telescope").setup({})
vim.o.columns = 160
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "foo foo" }, root .. "/a.txt")
local discover = root .. "/discover"
vim.fn.writefile({ "#!/bin/sh", "printf 'a.txt\\n'" }, discover)
vim.fn.setfperm(discover, "rwx------")
require("search_replace").setup({
  search = { debounce = 0, max_results = 1, command = { discover } },
  mappings = { i = { replace_current = "<C-E>", toggle_selection = "<C-T>", replace_selected_or_all = "<C-A>" } },
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
  local bufnr = picker.previewer and picker.previewer.state.bufnr
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then return "" end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, true)
  return ok and table.concat(lines, "\n") or ""
end

wait_for(function() return type(picker.manager) == "table" end, "picker initialization")
picker:set_prompt("")
wait_for(function()
  local text = preview()
  return text:find("<C-E>  Replace current occurrence", 1, true)
    and text:find("<C-T>  Toggle selection", 1, true)
    and text:find("<C-A>  Replace selected occurrences", 1, true)
end, "idle instructions")
picker:set_prompt("/foo")
wait_for(function()
  return type(picker.manager) == "table" and picker.manager:num_results() == 1 and preview():find(" 1 foo foo", 1, true)
end, "source preview")
picker:set_prompt("/foo/bar")
wait_for(function() return preview():find("+1 bar foo", 1, true) end, "single-occurrence diff")
picker:set_prompt("/foo/bar/g")
wait_for(function() return preview():find("+1 bar bar", 1, true) end, "global diff")

require("telescope.actions").close(prompt_bufnr)
require("telescope.builtin").resume()
prompt_bufnr = telescope_state.get_existing_prompt_bufnrs()[1]
status = telescope_state.get_status(prompt_bufnr)
assert(status.layout and status.picker.manager:num_results() == 1)
require("telescope.actions").close(prompt_bufnr)
print("telescope smoke test passed")
vim.cmd("qa!")
