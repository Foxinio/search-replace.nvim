local engine = require("search_replace.engine")
local transaction = require("search_replace.transaction")

local function matches(pattern, line)
  local found, err = engine.find_matches(pattern, line)
  assert(found, err)
  for _, match in ipairs(found) do match.original_text = line end
  return found
end

local three = matches("foo", "foo foo foo")
assert(#three == 3 and three[2].start_byte == 4)
assert(engine.compute("foo", "BAR", three[2], "foo foo foo").new_line == "foo BAR foo")
assert(engine.compute([[\vfoo_(\w+)]], [[new_\1]], matches([[\vfoo_(\w+)]], "foo_name")[1], "foo_name").new_line == "new_name")
assert(engine.compute([[xx\zsfoo\zeYY]], "BAR", matches([[xx\zsfoo\zeYY]], "xxfooYY")[1], "xxfooYY").new_line == "xxBARYY")
assert(engine.compute("^foo$", "bar", matches("^foo$", "foo")[1], "foo").new_line == "bar")
assert(engine.compute([[\c^foo$]], "bar", matches([[\c^foo$]], "FOO")[1], "FOO").new_line == "bar")
assert(engine.compute([[\v(foo)]], [[<&>-\1]], matches([[\v(foo)]], "foo")[1], "foo").new_line == "<foo>-foo")
assert(engine.compute([[\v(f)(oo)]], [[\2\1]], matches([[\v(f)(oo)]], "foo")[1], "foo").new_line == "oof")
assert(engine.compute("foo", [[\U&\E]], matches("foo", "foo")[1], "foo").new_line == "FOO")
assert(engine.compute("foo", [[\u&]], matches("foo", "foo")[1], "foo").new_line == "Foo")
assert(engine.compute("FOO", [[\l&]], matches("FOO", "FOO")[1], "FOO").new_line == "fOO")
assert(engine.compute("FOO", [[\L&\E]], matches("FOO", "FOO")[1], "FOO").new_line == "foo")
assert(engine.compute("foo", [[\\]], matches("foo", "foo")[1], "foo").new_line == [[\]])
assert(engine.compute("foo", "", matches("foo", "foo")[1], "foo").new_line == "")
assert(engine.compute("foo", [[x\ry]], matches("foo", "foo")[1], "foo").new_line == "x\ry")
assert(engine.compute("foo", [[x\ny]], matches("foo", "foo")[1], "foo").new_line == "x\ny")
assert(#matches([[foo\c]], "FOO foo") == 2)
assert(#matches([[foo\C]], "FOO foo") == 1)
assert(#matches([[\v(foo|bar)]], "foo bar") == 2)
assert(#matches([[\ze.]], "éa") == 2)
assert(engine.compute([[\ze.]], "x", matches([[\ze.]], "a")[1], "a").new_line == "xa")
assert(engine.find_matches("[", "x") == nil)
local unicode = matches("x", "éx")[1]
assert(unicode.start_byte == 2 and unicode.end_byte == 3)

local path = vim.fn.tempname()
vim.fn.writefile({ "foo foo foo" }, path)
for _, match in ipairs(three) do match.filename, match.lnum = path, 1 end
local result = transaction.run({ three[2] }, "foo", "LONG")
local bufnr = vim.fn.bufnr(path)
assert(result.applied == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, true)[1] == "foo LONG foo")
vim.api.nvim_buf_call(bufnr, function() vim.cmd("undo") end)
assert(vim.api.nvim_buf_get_lines(bufnr, 0, 1, true)[1] == "foo foo foo")
result = transaction.run(three, "foo", "x")
assert(result.applied == 3 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, true)[1] == "x x x")
assert(vim.bo[bufnr].modified)
vim.api.nvim_buf_call(bufnr, function() vim.cmd("undo") end)
assert(vim.api.nvim_buf_get_lines(bufnr, 0, 1, true)[1] == "foo foo foo")

assert(transaction.plan({ three[1], three[1] }, "foo", "x") == nil)
assert(transaction.targets(three, {}) == three)
assert(transaction.targets(three, { three[2] })[1] == three[2])

local second_path = vim.fn.tempname()
vim.fn.writefile({ "foo", "foo foo" }, second_path)
local cross = matches("foo", "foo")
cross[1].filename, cross[1].lnum = second_path, 1
local later = matches("foo", "foo foo")
for _, match in ipairs(later) do match.filename, match.lnum = second_path, 2 end
vim.list_extend(cross, later)
result = transaction.run(cross, "foo", "bar")
local second_buf = vim.fn.bufnr(second_path)
assert(result.applied == 3)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(second_buf, 0, -1, true), { "bar", "bar bar" }))

local modified_path = vim.fn.tempname()
vim.fn.writefile({ "disk" }, modified_path)
local modified_buf = vim.fn.bufadd(modified_path)
vim.fn.bufload(modified_buf)
vim.api.nvim_buf_set_lines(modified_buf, 0, -1, true, { "buffer foo" })
local modified_match = matches("foo", "buffer foo")[1]
modified_match.filename, modified_match.lnum = modified_path, 1
result = transaction.run({ modified_match }, "foo", "BAR")
assert(result.applied == 1 and vim.api.nvim_buf_get_lines(modified_buf, 0, -1, true)[1] == "buffer BAR")
assert(vim.fn.readfile(modified_path)[1] == "disk")

local newline_path = vim.fn.tempname()
vim.fn.writefile({ "foo" }, newline_path)
local newline_match = matches("foo", "foo")[1]
newline_match.filename, newline_match.lnum = newline_path, 1
result = transaction.run({ newline_match }, "foo", [[x\ny]])
assert(result.applied == 1)
assert(vim.api.nvim_buf_get_lines(vim.fn.bufnr(newline_path), 0, -1, true)[1] == "x\0y")

vim.api.nvim_buf_set_lines(bufnr, 0, 1, true, { "changed" })
result = transaction.run({ three[1] }, "foo", "x")
assert(result.applied == 0 and result.stale == 1)
print("domain tests passed")
vim.cmd("qa!")
