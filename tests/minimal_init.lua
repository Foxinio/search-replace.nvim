vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.env.EDITABLE_TELESCOPE_PATH or (vim.fn.stdpath("data") .. "/lazy/editable-telescope.nvim"))
