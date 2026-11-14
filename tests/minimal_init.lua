local deps = vim.env.DEPS_DIR
if not deps or deps == "" then deps = vim.fn.stdpath("data") .. "/lazy" end
local editable = vim.env.EDITABLE_TELESCOPE_PATH
if not editable or editable == "" then editable = deps .. "/editable-telescope.nvim" end
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(editable)
vim.opt.runtimepath:prepend(deps .. "/plenary.nvim")
vim.opt.runtimepath:prepend(deps .. "/telescope.nvim")

require("telescope").setup({})
