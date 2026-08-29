local M = {}

function M.setup(opts)
  require("search_replace.config").setup(opts)
end

function M.open(opts)
  require("search_replace.picker").open(opts)
end

return M
