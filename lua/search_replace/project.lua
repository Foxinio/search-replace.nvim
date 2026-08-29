local engine = require("search_replace.engine")

local M = {}

local function under(path, root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function loaded_lines(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr >= 0 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  end
end

local function read(path, callback)
  local lines = loaded_lines(path)
  if lines then return callback(lines) end
  local uv = vim.uv or vim.loop
  uv.fs_open(path, "r", 438, function(open_err, fd)
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
          callback(vim.split(data, "\n", { plain = true }))
        end)
      end)
    end)
  end)
end

local function command(config)
  if config.command then return vim.deepcopy(config.command), false end
  local cmd = { "rg", "--files", "--null" }
  if config.hidden then cmd[#cmd + 1] = "--hidden" end
  if config.ignored then cmd[#cmd + 1] = "--no-ignore" end
  for _, glob in ipairs(config.globs or {}) do
    vim.list_extend(cmd, { "--glob", glob })
  end
  return cmd, true
end

function M.cancel(state)
  if state.search_job then pcall(state.search_job.kill, state.search_job, 15) end
  state.search_job = nil
end

---Discover asynchronously, then scan files in small concurrent batches.
function M.search(state, config, done)
  M.cancel(state)
  state.search_generation = state.search_generation + 1
  local generation, cwd, pattern = state.search_generation, state.cwd, state.search_pattern
  if pattern == "" then return done({}, nil, generation) end
  if pattern:find("\n", 1, true) or pattern:find([[\_]], 1, true) then
    return done({}, "multiline patterns are not supported", generation)
  end
  local _, regex_err = engine.find_matches(pattern, "")
  if regex_err then return done({}, regex_err, generation) end

  local cmd, nul = command(config)
  state.search_job = vim.system(cmd, { cwd = cwd, text = false }, function(result)
    vim.schedule(function()
      if generation ~= state.search_generation then return end
      state.search_job = nil
      if result.code ~= 0 then
        return done({}, result.stderr ~= "" and result.stderr or "file discovery failed", generation)
      end
      local paths, seen = {}, {}
      for name in result.stdout:gmatch(nul and "([^%z]+)" or "([^\n]+)") do
        local path = vim.fs.normalize(name:sub(1, 1) == "/" and name or vim.fs.joinpath(cwd, name))
        if not seen[path] then paths[#paths + 1], seen[path] = path, true end
      end
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name ~= "" then
          name = vim.fs.normalize(name)
          if under(name, cwd) and not seen[name] then paths[#paths + 1], seen[name] = name, true end
        end
      end
      table.sort(paths)

      local results, next_path, active = {}, 1, 0
      local function pump()
        if generation ~= state.search_generation then return end
        while active < 8 and next_path <= #paths do
          local filename = paths[next_path]
          next_path, active = next_path + 1, active + 1
          read(filename, function(lines)
            active = active - 1
            if generation ~= state.search_generation then return end
            if lines then
              for index, line in ipairs(lines) do
                line = line:gsub("\r$", "")
                local found, err = engine.find_matches(pattern, line)
                if err then return done({}, err, generation) end
                for _, match in ipairs(found) do
                  match.filename = filename
                  match.lnum = index
                  match.original_text = line
                  match.id = table.concat({ filename, index, match.start_byte, match.end_byte, line }, "\0")
                  results[#results + 1] = match
                end
              end
            end
            if next_path > #paths and active == 0 then
              table.sort(results, function(a, b)
                return a.filename < b.filename
                  or (a.filename == b.filename and (a.lnum < b.lnum
                    or (a.lnum == b.lnum and a.start_byte < b.start_byte)))
              end)
              done(results, nil, generation)
            else
              pump()
            end
          end)
        end
        if #paths == 0 then done({}, nil, generation) end
      end
      pump()
    end)
  end)
end

return M
