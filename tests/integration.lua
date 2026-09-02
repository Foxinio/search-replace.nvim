local engine = require("search_replace.engine")
local project = require("search_replace.project")
local transaction = require("search_replace.transaction")

local validate, validations = engine.validate, 0
engine.validate = function(...)
  validations = validations + 1
  return validate(...)
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "disk foo" }, root .. "/a.txt")
vim.fn.writefile({ "foo foo bar", "keep foo" }, root .. "/b.txt")
vim.fn.writefile({ "disk foo" }, root .. "/d.txt")

local a_buf = vim.fn.bufadd(root .. "/a.txt")
vim.fn.bufload(a_buf)
vim.api.nvim_buf_set_lines(a_buf, 0, -1, true, { "buffer foo" })
local d_buf = vim.fn.bufadd(root .. "/d.txt")
vim.fn.bufload(d_buf)

local count = root .. "/count"
local discover = root .. "/discover"
vim.fn.writefile({ "#!/bin/sh", "printf x >> '" .. count .. "'", "sleep 0.05", "printf 'a.txt\\nb.txt\\nd.txt\\n'" }, discover)
vim.fn.setfperm(discover, "rwx------")
local config = { command = { discover }, max_results = 1, hidden = false, ignored = false, globs = {} }
local state = { search_pattern = "foo", search_generation = 0, cwd = root, files = {}, files_by_name = {}, matches = {} }
local obsolete_called = false
local progress_updates = 0

local function searches(pattern, callback)
  state.search_pattern = pattern
  project.search(state, config, function(found, err)
    assert(not err, err)
    callback(found)
  end, function(found)
    assert(#found <= config.max_results)
    progress_updates = progress_updates + 1
  end)
end

project.search(state, config, function() obsolete_called = true end)
searches("bar", function(bar)
  assert(not obsolete_called, "obsolete discovery waiter ran")
  assert(#bar == 1 and vim.fn.readfile(count)[1] == "x")
  searches("foo", function(foo)
    assert(#foo == 5 and foo[1].original_text == "buffer foo")
    assert(vim.fn.readfile(root .. "/a.txt")[1] == "disk foo")
    local old_b_lines = state.files_by_name[root .. "/b.txt"].lines
    searches([[foo\c]], function(same_disk)
      assert(#same_disk == 5 and state.files_by_name[root .. "/b.txt"].lines == old_b_lines)

      vim.fn.writefile({ "fresh foo foo foo", "keep foo" }, root .. "/b.txt")
      vim.fn.writefile({ "newer foo foo" }, root .. "/d.txt")
      vim.fn.writefile({ "foo" }, root .. "/new.txt")
      searches("foo", function(changed_disk)
        assert(#changed_disk == 6, vim.inspect(changed_disk))
        assert(#state.files_by_name[root .. "/b.txt"].lines == 2)
        assert(not state.files_by_name[root .. "/new.txt"])
        assert(state.files_by_name[root .. "/b.txt"].lines ~= old_b_lines)
        assert(project.lines(state, root .. "/d.txt")[1] == "disk foo")
        assert(vim.api.nvim_buf_get_lines(d_buf, 0, 1, true)[1] == "disk foo")
        assert(vim.fn.readfile(count)[1] == "x")
        for index = 2, #changed_disk do
          local before, after = changed_disk[index - 1], changed_disk[index]
          assert(before.filename < after.filename
            or (before.filename == after.filename and (before.lnum < after.lnum
              or (before.lnum == after.lnum and before.start_byte <= after.start_byte))))
        end

        local target
        for _, match in ipairs(changed_disk) do
          if match.filename == root .. "/b.txt" then target = match break end
        end
        local untouched = state.files_by_name[root .. "/b.txt"].matches_by_line[2]
        local result = transaction.run({ target }, "foo", "foo foo")
        assert(result.applied == 1 and result.changes[target.filename].lines[1])
        local refreshed, refresh_err = project.refresh(state, result.changes)
        assert(not refresh_err, refresh_err)
        assert(#refreshed == 7 and state.files_by_name[root .. "/b.txt"].matches_by_line[2] == untouched)

        target = state.files_by_name[root .. "/b.txt"].matches_by_line[1][1]
        result = transaction.run({ target }, "foo", "x", true)
        assert(result.applied == 1)
        refreshed, refresh_err = project.refresh(state, result.changes)
        assert(not refresh_err, refresh_err)
        assert(#refreshed == 3)

        target = state.files_by_name[root .. "/a.txt"].matches_by_line[1][1]
        result = transaction.run({ target }, "foo", [[foo\rfoo]])
        assert(result.applied == 1 and result.changes[target.filename].line_structure_changed)
        refreshed, refresh_err = project.refresh(state, result.changes)
        assert(not refresh_err, refresh_err)
        assert(#refreshed == 4)
        assert(#state.files_by_name[root .. "/a.txt"].lines == 2)
        assert(vim.fn.readfile(count)[1] == "x")
        assert(validations == 5)
        assert(progress_updates > 0)

        print("project integration tests passed")
        vim.cmd("qa!")
      end)
    end)
  end)
end)
