local config = require("search_replace.config")
local engine = require("search_replace.engine")
local project = require("search_replace.project")
local prompt = require("search_replace.prompt")
local transaction = require("search_replace.transaction")
local args = require("search_replace.args")

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
-- TODO: Check if it is possible to refactor this function
  local result = require("telescope.previewers").new_buffer_previewer({
    title = "Replacement preview",
    define_preview = function(self, selected)
      vim.api.nvim_buf_clear_namespace(self.state.bufnr, preview_ns, 0, -1)
      if state.search_error then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Search error:", state.search_error })
        return
      end
      if state.parse_error then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Prompt error:", state.parse_error })
        return
      end
      if state.mode == "idle" then
        local mappings = config.values.mappings.i
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
          "Enter /pattern/replacement/g",
          "Any non-alphanumeric single-byte delimiter works.",
          "",
          "Key bindings:",
          mappings.replace_current .. "  Replace current occurrence",
          mappings.toggle_selection .. "  Toggle selection",
          mappings.replace_selected_or_all .. "  Replace selected occurrences, or all when none are selected",
          mappings.change_root .. "  Change search root",
          mappings.edit_search_args .. "  Edit rg flags",
        })
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
      local lines, first
      if state.mode == "search" then
        lines, first = current_lines(state, match, config.values.preview.context)
      else
        lines, first = project.lines(state, match.filename), 1
      end
      if not lines then
        local reason = state.mode == "search" and first or "missing cached file"
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Preview unavailable: " .. reason })
        return
      end
      local line = lines[match.lnum - first + 1]
      if state.mode == "search" then
        local out = {}
        for index, text in ipairs(lines) do out[index] = (" %d %s"):format(first + index - 1, text) end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, out)
        local row, prefix = match.lnum - first, #(" " .. match.lnum .. " ")
        pcall(vim.api.nvim_buf_set_extmark, self.state.bufnr, preview_ns, row, prefix + match.start_byte,
          { end_col = prefix + match.end_byte, hl_group = "Search" })
        vim.schedule(function() pcall(vim.api.nvim_win_set_cursor, self.state.winid, { row + 1, 0 }) end)
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
      vim.schedule(function() pcall(vim.api.nvim_win_set_cursor, self.state.winid, { match.lnum, 0 }) end)
    end,
  })
  local preview = result.preview
  function result:preview(selected, status)
    return preview(self, selected or {}, status)
  end
  return result
end

local function open(opts, search_config, editor)
  search_config = vim.tbl_extend("force", {}, search_config, { args = editor.cmd_args })
  local arg_error = editor.cmd_args_error
  -- editable-telescope hands over an already normalized root.
  local cwd = opts.cwd
  local state = {
    pattern = "",
    search_pattern = "",
    replacement = nil,
    flags = { global = false },
    mode = "idle",
    parse_error = nil,
    search_generation = 0,
    matches = {},
    searching = false,
    files = {},
    files_by_name = {},
    cwd = cwd,
    search_error = arg_error,
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
      displayed = vim.list_slice(displayed, 1, search_config.max_results)
      picker:refresh(finders.new_table({ results = displayed, entry_maker = function(m) return entry(m, cwd) end }), { reset_prompt = false })
    end
  end
  local function refresh_preview()
    if active() then picker:refresh_previewer() end
  end
  local function search()
    if not active() then return end
    if arg_error then
      state.matches, state.search_error, state.searching = {}, arg_error, false
      refresh_results()
      refresh_preview()
      return
    end
    state.searching = true
    project.search(state, search_config, function(matches, err, generation)
      if generation ~= state.search_generation then return end
      state.matches, state.search_error, state.searching = matches, err, false
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
    timer:start(search_config.debounce, 0, vim.schedule_wrap(search))
  end
  local function apply(matches)
    if state.mode ~= "replace" or state.parse_error then return end
    if state.search_error then return end
    if state.searching then return vim.notify("search still in progress", vim.log.levels.INFO) end
    if not matches or #matches == 0 then return end
    local result = transaction.run(matches, state.pattern, state.replacement, state.flags.global)
    if result.error then
      vim.notify(result.error, vim.log.levels.ERROR)
    elseif result.stale > 0 then
      vim.notify(("replaced %d; skipped %d stale matches"):format(result.applied, result.stale), vim.log.levels.WARN)
    end
    if result.stale > 0 then
      search()
    elseif result.applied > 0 then
      local refreshed, refresh_err = project.refresh(state, result.changes)
      state.matches, state.search_error = refreshed or {}, refresh_err
      refresh_results()
    end
  end

  local picker_opts = vim.tbl_extend("force", {}, opts, { cwd = cwd })
  picker_opts.attach_mappings = nil
  picker = pickers.new(picker_opts, {
    prompt_prefix = "S/R: ",
    history = false,
    selection_strategy = "row",
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
      return not opts.attach_mappings or opts.attach_mappings(prompt_bufnr, map)
    end,
  })
  picker:find()
  if arg_error then
    vim.schedule(function()
      refresh_results()
      refresh_preview()
    end)
  end
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

-- Minimum editable-telescope: the release providing editable_picker,
-- args.format, strict args.split and args.normalize_root.
function M.editable_telescope()
  local ok, shared = pcall(require, "editable-telescope.args")
  local ext_ok, ext = pcall(function() return require("telescope").extensions.editable end)
  if not ok or not ext_ok or type(ext) ~= "table" then
    error("search-replace.nvim requires Foxinio/editable-telescope.nvim")
  end
  if type(shared.format) ~= "function" or type(shared.normalize_root) ~= "function"
    or type(ext.editable_picker) ~= "function" then
    error("search-replace.nvim requires a newer editable-telescope.nvim (editable_picker, args.normalize_root)")
  end
  return shared
end

function M.open(opts)
  if vim.fn.has("nvim-0.10") == 0 then error("search-replace.nvim requires Neovim 0.10+") end
  local ok, telescope = pcall(require, "telescope")
  if not ok then error("search-replace.nvim requires telescope.nvim") end
  opts = opts or {}
  local search_config = vim.tbl_deep_extend("force", vim.deepcopy(config.values.search), opts.search or {})
  for _, key in ipairs({ "args", "globs", "command" }) do
    if opts.search and opts.search[key] ~= nil then search_config[key] = vim.deepcopy(opts.search[key]) end
  end
  if vim.fn.executable("rg") == 0 and not search_config.command then
    error("search-replace.nvim requires rg for file discovery")
  end
  local shared = M.editable_telescope()
  local cwd, cwd_err = shared.normalize_root(opts.cwd)
  if not cwd then error(cwd_err) end
  local mappings = config.values.mappings.i
  telescope.extensions.editable.editable_picker({
    picker_opts = opts,
    initial_state = {
      cwd = cwd,
      cmd_args = search_config.args,
      cmd_args_text = shared.format(search_config.args),
      cmd_args_error = not search_config.command and args.validate(search_config.args) or nil,
    },
    mappings = { change_root = mappings.change_root, edit_args = mappings.edit_search_args },
    cmd_args_prompt = "rg flags: ",
    parse_cmd_args = function(input)
      if search_config.command then
        if input ~= "" then return nil, "rg flags are unavailable with a custom discovery command" end
        return search_config.args
      end
      return args.parse(input)
    end,
    format_cmd_args = function(_, editor) return editor.cmd_args_text end,
    prompt_title = function(editor)
      return "Search and replace — " .. vim.fs.normalize(editor.cwd) .. " [" .. editor.cmd_args_text .. "]"
    end,
    open = function(editor, picker_opts) open(picker_opts, search_config, editor) end,
  })
end

return M
