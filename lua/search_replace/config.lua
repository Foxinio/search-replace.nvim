local M = {}

M.defaults = {
  search = { debounce = 100, hidden = false, ignored = false, globs = {}, command = nil },
  preview = { context = 3 },
  replace = { auto_save = false },
  mappings = {
    i = {
      replace_current = "<CR>",
      toggle_selection = "<Tab>",
      replace_selected_or_all = "<C-r>",
    },
  },
}

M.values = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
