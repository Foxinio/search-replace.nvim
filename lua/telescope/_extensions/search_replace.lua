return require("telescope").register_extension({
  exports = {
    search_replace = require("search_replace").open,
  },
})
