local project = require("search_replace.project")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/vendor", "p")
for _, name in ipairs({ "a.lua", "a.txt", ".hidden.lua", "ignored.lua", "vendor/a.lua" }) do
  vim.fn.writefile({ "foo" }, root .. "/" .. name)
end
vim.fn.writefile({ "ignored.lua" }, root .. "/.ignore")
local excluded = vim.fn.bufadd(root .. "/vendor/a.lua")
vim.fn.bufload(excluded)
local included = vim.fn.bufadd(root .. "/a.lua")
vim.fn.bufload(included)
vim.api.nvim_buf_set_lines(included, 0, -1, true, { "foo foo" })

local function search(flags, expected_error)
  local finished, found, failure = false
  local state = { cwd = root, search_pattern = "foo", search_generation = 0 }
  project.search(state, { args = flags }, function(matches, err)
    found, failure, finished = matches, err, true
  end)
  assert(vim.wait(3000, function() return finished end, 10), "discovery timed out")
  if expected_error then
    assert(failure and failure:find(expected_error, 1, true), failure)
  else
    assert(not failure, failure)
  end
  return found
end

local matches = search({ "-g", "!vendor/**" })
assert(#matches == 3 and matches[1].filename == root .. "/a.lua", vim.inspect(matches))
assert(#search({ "-g", "*.lua", "-g", "!vendor/**" }) == 4)
assert(#search({ "-t", "lua", "-g", "!vendor/**", "--hidden", "--no-ignore" }) == 4)
assert(#search({ "-g", "*.missing" }) == 0)
assert(#search({ "-t", "lua", "--max-depth", "1" }) == 3)
assert(#search({ "--max-depth", "invalid" }, "invalid") == 0)
print("file filter tests passed")
vim.cmd("qa!")
