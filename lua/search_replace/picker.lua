local config = require("search_replace.config")
local engine = require("search_replace.engine")
local project = require("search_replace.project")
local prompt = require("search_replace.prompt")
local transaction = require("search_replace.transaction")

local M = {}
local preview_ns = vim.api.nvim_create_namespace("search_replace_preview")

local function entry(match, cwd)
  if match.error then
    return { value = match, ordinal = match.id, display = "Error: " .. match.error }
  end
  local relative = vim.fn.fnamemodify(match.filename, ":.")
  if match.filename:sub(1, #cwd + 1) == cwd .. "/" then relative = match.filename:sub(#cwd + 2) end
  return {
    value = match,
    ordinal = match.id,
    filename = match.filename,
    lnum = match.lnum,
    col = match.start_byte + 1,
    display = ("%s:%d:%d    %s"):format(relative, match.lnum, match.start_byte + 1, match.original_text),
  }
end

local function current_lines(state, match, context)
  local lines = project.lines(state, match.filename)
  if not lines then return nil, "missing cached file" end
  local first = math.max(1, match.lnum - context)
  return vim.list_slice(lines, first, match.lnum + context), first
end

local function previewer(state)
  return require("telescope.previewers").new_buffer_previewer({
    title = "Replacement preview",
    define_preview = function(self, selected)
      vim.api.nvim_buf_clear_namespace(self.state.bufnr, preview_ns, 0, -1)
      if state.mode == "idle" then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Enter /pattern/replacement/g", "Any non-alphanumeric single-byte delimiter works." })
        return
      end
      if state.parse_error then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Prompt error:", state.parse_error })
        return
      end
      local match = selected and selected.value
      if not match then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {})
        return
      end
      if match.error then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Search error:", match.error })
        return
      end
      local lines, first = current_lines(state, match, config.values.preview.context)
      if not lines then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { first })
        return
      end
      local line = lines[match.lnum - first + 1]
      if state.mode == "search" then
        local out = {}
        for index, text in ipairs(lines) do out[index] = (" %d %s"):format(first + index - 1, text) end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, out)
        local row, prefix = match.lnum - first, #(" " .. match.lnum .. " ")
        vim.api.nvim_buf_add_highlight(self.state.bufnr, preview_ns, "Search", row, prefix + match.start_byte, prefix + match.end_byte)
        return
      end
      local computed, err = engine.compute(state.pattern, state.replacement, match, line, state.flags.global)
      local out = {}
      for index, text in ipairs(lines) do
        local lnum = first + index - 1
        if lnum == match.lnum then
          out[#out + 1] = ("-%d %s"):format(lnum, text)
          if computed then
            for _, replacement_line in ipairs(vim.split(computed.new_line, "\r", { plain = true })) do
              out[#out + 1] = ("+%d %s"):format(lnum, replacement_line:gsub("\n", "\0"))
            end
          else
            out[#out + 1] = "! " .. err
          end
        else
          out[#out + 1] = (" %d %s"):format(lnum, text)
        end
      end
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, out)
      vim.bo[self.state.bufnr].filetype = "diff"
    end,
  })
end

function M.open(opts)
  if vim.fn.has("nvim-0.10") == 0 then error("search-replace.nvim requires Neovim 0.10+") end
  local ok = pcall(require, "telescope")
  if not ok then error("search-replace.nvim requires telescope.nvim") end
  if vim.fn.executable("rg") == 0 and not config.values.search.command then
    error("search-replace.nvim requires rg for file discovery")
  end

  opts = opts or {}
  local cwd = vim.fs.normalize(opts.cwd or vim.uv.cwd())
  if vim.fn.isdirectory(cwd) == 0 then error("invalid cwd: " .. cwd) end
  local state = {
    pattern = "",
    search_pattern = "",
    replacement = nil,
    flags = { global = false },
    mode = "idle",
    parse_error = nil,
    search_generation = 0,
    matches = {},
    files = {},
    files_by_name = {},
    cwd = cwd,
  }
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local sorters = require("telescope.sorters")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local telescope_state = require("telescope.state")
  local timer = vim.uv.new_timer()
  local picker

  local function active()
    return picker and picker.prompt_bufnr and telescope_state.get_status(picker.prompt_bufnr).layout
  end
  local function refresh_results()
    if active() and vim.api.nvim_buf_is_valid(picker.prompt_bufnr) then
      local displayed = state.search_error and { { error = state.search_error, id = state.search_error } } or state.matches
      displayed = vim.list_slice(displayed, 1, config.values.search.max_results)
      picker:refresh(finders.new_table({ results = displayed, entry_maker = function(m) return entry(m, cwd) end }), { reset_prompt = false })
    end
  end
  local function refresh_preview()
    if active() then picker:refresh_previewer() end
  end
  local function search()
    project.search(state, config.values.search, function(matches, err, generation)
      if generation ~= state.search_generation then return end
      state.matches, state.search_error = matches, err
      refresh_results()
    end, function(matches, generation)
      if generation ~= state.search_generation then return end
      state.matches, state.search_error = matches, nil
      refresh_results()
    end)
  end
  local function schedule_search()
    timer:stop()
    state.search_generation = state.search_generation + 1
    timer:start(config.values.search.debounce, 0, vim.schedule_wrap(search))
  end
  local function apply(matches)
    if state.mode ~= "replace" or state.parse_error then return end
    if not matches or #matches == 0 then return end
    local result = transaction.run(matches, state.pattern, state.replacement, state.flags.global)
    if result.error then
      vim.notify(result.error, vim.log.levels.ERROR)
    elseif result.stale > 0 then
      vim.notify(("replaced %d; skipped %d stale matches"):format(result.applied, result.stale), vim.log.levels.WARN)
    end
    if result.applied > 0 then
      local refreshed, refresh_err = project.refresh(state, result.changes)
      state.matches, state.search_error = refreshed or {}, refresh_err
      refresh_results()
    end
  end

  picker = pickers.new(opts, {
    prompt_title = "Search and replace — " .. cwd,
    prompt_prefix = "S/R: ",
    default_text = "/",
    history = false,
    finder = finders.new_table({ results = {} }),
    sorter = sorters.empty(),
    previewer = previewer(state),
    attach_mappings = function(prompt_bufnr, map)
      prompt.attach(prompt_bufnr, state, function(pattern_changed)
        state.search_pattern = state.pattern
        if pattern_changed then schedule_search() else refresh_preview() end
      end)
      local mappings = config.values.mappings.i
      map("i", mappings.replace_current, function()
        if state.mode ~= "replace" or state.parse_error then return end
        local selected = action_state.get_selected_entry()
        if selected and not selected.value.error then apply({ selected.value }) end
      end)
      map("i", mappings.toggle_selection, actions.toggle_selection)
      map("i", mappings.replace_selected_or_all, function()
        if state.mode ~= "replace" or state.parse_error then return end
        local current = action_state.get_current_picker(prompt_bufnr)
        local selected = current:get_multi_selection()
        local targets = {}
        for _, item in ipairs(selected) do targets[#targets + 1] = item.value end
        apply(transaction.targets(state.matches, targets))
      end)
      return true
    end,
  })
  picker:find()
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = picker.prompt_bufnr,
    once = true,
    callback = function()
      timer:stop()
      timer:close()
      project.cancel(state)
    end,
  })
end

return M
