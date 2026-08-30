local engine = require("search_replace.engine")

local M = {}
local uv = vim.uv or vim.loop

local function under(path, root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function add_file(state, filename)
  local record = state.files_by_name[filename]
  if record then return record end
  record = { filename = filename, lines = {}, matches_by_line = {} }
  state.files_by_name[filename] = record
  state.files[#state.files + 1] = record
  return record
end

local function add_loaded_files(state)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      name = vim.fs.normalize(name)
      if under(name, state.cwd) then add_file(state, name) end
    end
  end
  table.sort(state.files, function(a, b) return a.filename < b.filename end)
end

local function signature(stat)
  return stat.size, stat.mtime.sec, stat.mtime.nsec
end

local function same_disk(record, stat)
  local size, sec, nsec = signature(stat)
  return record.from_disk and record.size == size and record.mtime_sec == sec and record.mtime_nsec == nsec
end

local function remember_disk(record, stat, lines)
  record.size, record.mtime_sec, record.mtime_nsec = signature(stat)
  record.lines, record.from_disk = lines, true
end

local function read_disk(record, _, callback)
  uv.fs_open(record.filename, "r", 438, function(open_err, fd)
    if open_err then return vim.schedule(function() callback(nil, open_err) end) end
    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err then
        uv.fs_close(fd)
        return vim.schedule(function() callback(nil, stat_err) end)
      end
      uv.fs_read(fd, stat.size, 0, function(read_err, data)
        uv.fs_close(fd)
        vim.schedule(function()
          if read_err then return callback(nil, read_err) end
          if data:find("\0", 1, true) then return callback(nil, "binary") end
          callback(vim.split(data, "\n", { plain = true }), nil, stat, true)
        end)
      end)
    end)
  end)
end

local function source(record, callback)
  local bufnr = vim.fn.bufnr(record.filename)
  if bufnr >= 0 and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified then
    return callback(vim.api.nvim_buf_get_lines(bufnr, 0, -1, true), nil, nil, false)
  end
  uv.fs_stat(record.filename, function(err, stat)
    vim.schedule(function()
      if err then return callback(nil, err) end
      if same_disk(record, stat) then return callback(record.lines, nil, nil, true) end
      read_disk(record, stat, callback)
    end)
  end)
end

local function command(config)
  if config.command then return vim.deepcopy(config.command), false end
  local cmd = { "rg", "--files", "--null" }
  if config.hidden then cmd[#cmd + 1] = "--hidden" end
  if config.ignored then cmd[#cmd + 1] = "--no-ignore" end
  for _, glob in ipairs(config.globs or {}) do vim.list_extend(cmd, { "--glob", glob }) end
  return cmd, true
end

local function occurrence(record, lnum, line, match)
  match.filename, match.lnum, match.original_text = record.filename, lnum, line
  match.id = table.concat({ record.filename, lnum, match.start_byte, match.end_byte, line }, "\0")
  return match
end

local function scan_line(record, lnum, line, pattern)
  line = line:gsub("\r$", "")
  local found, err = engine.find_matches(pattern, line, true)
  if not found then return nil, err end
  for _, match in ipairs(found) do occurrence(record, lnum, line, match) end
  return found, nil, line
end

local function scan_record(record, lines, pattern)
  local buckets = {}
  for lnum, line in ipairs(lines) do
    local found, err, clean = scan_line(record, lnum, line, pattern)
    if not found then return nil, err end
    lines[lnum], buckets[lnum] = clean, found
  end
  record.lines, record.matches_by_line = lines, buckets
  return true
end

local function flatten(state)
  local matches = {}
  for _, record in ipairs(state.files) do
    for lnum = 1, #record.lines do
      vim.list_extend(matches, record.matches_by_line[lnum] or {})
    end
  end
  state.matches = matches
  return matches
end

local function scan(state, pattern, generation, done)
  add_loaded_files(state)
  local next_file, active, finished = 1, 0, false
  local function finish(err)
    if finished or generation ~= state.search_generation then return end
    finished = true
    done(err and {} or flatten(state), err, generation)
  end
  local function pump()
    if finished or generation ~= state.search_generation then return end
    while active < 8 and next_file <= #state.files do
      local record = state.files[next_file]
      next_file, active = next_file + 1, active + 1
      source(record, function(lines, err, stat, from_disk)
        active = active - 1
        if finished or generation ~= state.search_generation then return end
        if not lines then
          record.lines, record.matches_by_line = {}, {}
        else
          if stat then
            remember_disk(record, stat, lines)
          elseif not from_disk then
            record.lines, record.from_disk = lines, false
          end
          local ok, scan_err = scan_record(record, record.lines, pattern)
          if not ok then return finish(scan_err) end
        end
        if next_file > #state.files and active == 0 then finish() else pump() end
      end)
    end
    if #state.files == 0 then finish() end
  end
  pump()
end

local function discover(state, config)
  local cmd, nul = command(config)
  state.discovery_pending = true
  state.search_job = vim.system(cmd, { cwd = state.cwd, text = false }, function(result)
    vim.schedule(function()
      state.discovery_pending, state.search_job = false, nil
      local waiter = state.discovery_waiter
      state.discovery_waiter = nil
      if result.code ~= 0 then
        if waiter and waiter.generation == state.search_generation then
          waiter.done({}, result.stderr ~= "" and result.stderr or "file discovery failed", waiter.generation)
        end
        return
      end
      for name in result.stdout:gmatch(nul and "([^%z]+)" or "([^\n]+)") do
        local filename = vim.fs.normalize(name:sub(1, 1) == "/" and name or vim.fs.joinpath(state.cwd, name))
        add_file(state, filename)
      end
      state.discovered = true
      table.sort(state.files, function(a, b) return a.filename < b.filename end)
      if waiter and waiter.generation == state.search_generation then
        scan(state, waiter.pattern, waiter.generation, waiter.done)
      end
    end)
  end)
end

function M.cancel(state)
  state.search_generation = state.search_generation + 1
  state.discovery_waiter = nil
  if state.search_job then pcall(state.search_job.kill, state.search_job, 15) end
  state.search_job, state.discovery_pending = nil, false
end

function M.search(state, config, done)
  state.files, state.files_by_name = state.files or {}, state.files_by_name or {}
  state.search_generation = state.search_generation + 1
  local generation, pattern = state.search_generation, state.search_pattern
  state.discovery_waiter = nil
  if pattern == "" then
    state.matches = {}
    return done({}, nil, generation)
  end
  if pattern:find("\n", 1, true) or pattern:find([[\_]], 1, true) then
    return done({}, "multiline patterns are not supported", generation)
  end
  local regex_err = engine.validate(pattern)
  if regex_err then return done({}, regex_err, generation) end
  if state.discovered then return scan(state, pattern, generation, done) end
  state.discovery_waiter = { pattern = pattern, generation = generation, done = done }
  if not state.discovery_pending then discover(state, config) end
end

function M.refresh(state, changes)
  local pattern = state.search_pattern
  for filename, change in pairs(changes or {}) do
    local record = state.files_by_name and state.files_by_name[filename]
    if record then
      if change.line_structure_changed then
        record.lines = vim.api.nvim_buf_get_lines(change.bufnr, 0, -1, true)
        record.from_disk = false
        local ok, err = scan_record(record, record.lines, pattern)
        if not ok then return nil, err end
      else
        for lnum in pairs(change.lines) do
          local line = vim.api.nvim_buf_get_lines(change.bufnr, lnum - 1, lnum, true)[1]
          if line then
            local found, err, clean = scan_line(record, lnum, line, pattern)
            if not found then return nil, err end
            record.lines[lnum], record.matches_by_line[lnum] = clean, found
          end
        end
        record.from_disk = false
      end
    end
  end
  return flatten(state)
end

function M.lines(state, filename)
  local record = state.files_by_name and state.files_by_name[filename]
  return record and record.lines
end

return M
