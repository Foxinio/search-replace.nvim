local project = require("search_replace.project")

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "disk foo" }, root .. "/a.txt")
vim.fn.writefile({ "foo foo bar" }, root .. "/b.txt")

local bufnr = vim.fn.bufadd(root .. "/a.txt")
vim.fn.bufload(bufnr)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { "buffer foo" })

local state = { search_pattern = "foo", search_generation = 0, cwd = root }
project.search(state, { debounce = 0, hidden = false, ignored = false, globs = {} }, function(found, err)
  assert(not err, err)
  assert(#found == 3, vim.inspect(found))
  assert(found[1].original_text == "buffer foo")
  assert(vim.fn.readfile(root .. "/a.txt")[1] == "disk foo")
  local obsolete_called = false
  state.search_pattern = "foo"
  project.search(state, { hidden = false, ignored = false, globs = {} }, function()
    obsolete_called = true
  end)
  state.search_pattern = "bar"
  project.search(state, { hidden = false, ignored = false, globs = {} }, function(newer, newer_err)
    assert(not newer_err, newer_err)
    assert(#newer == 1 and newer[1].matched_text == "bar")
    vim.defer_fn(function()
      assert(not obsolete_called, "obsolete search callback ran")
      print("project integration test passed")
      vim.cmd("qa!")
    end, 50)
  end)
end)
