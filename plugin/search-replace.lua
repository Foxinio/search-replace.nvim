if vim.g.loaded_search_replace then return end
vim.g.loaded_search_replace = true

vim.api.nvim_create_user_command("SearchReplace", function(command)
  require("search_replace").open({ cwd = command.args ~= "" and command.args or nil })
end, { nargs = "?", complete = "dir", desc = "Project-wide Vim search and replace" })
