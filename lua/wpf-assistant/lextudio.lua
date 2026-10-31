-- LeXtudio backend: project build/output discovery and named-pipe synchronization.
local M = {}
local sessions = {}
local uv = vim.uv
-- Native camera SDK DLLs must remain on disk, but cannot be loaded as CLR assemblies.
local function managed_dll(path)
  local f = io.open(path, 'rb')
  if not f then return false end
  local function number(offset, count)
    f:seek('set', offset)
    local bytes = f:read(count)
    if not bytes or #bytes ~= count then return 0 end
    local value = 0
    for i = count, 1, -1 do value = value * 256 + bytes:byte(i) end
    return value
  end
  local pe = number(60, 4)
  f:seek('set', pe)
  local signature = f:read(4)
  local magic = number(pe + 24, 2)
  local directory = magic == 267 and 96 or magic == 523 and 112 or nil
  local managed = signature == 'PE\0\0' and directory ~= nil
    and number(pe + 24 + directory + 14 * 8, 4) ~= 0
  f:close()
  return managed
end
local function tools() return vim.g.wpf_tools_root or 'D:/install/wpf-nvim-tools' end
local function run(args, callback)
  vim.system(args, { text = true }, vim.schedule_wrap(function(r)
    if r.code ~= 0 then vim.notify(r.stderr .. r.stdout, vim.log.levels.ERROR) else callback(r.stdout) end
  end))
end
local function send(session, file)
  local text = table.concat(vim.fn.readfile(file), '\n')
  local pipe = uv.new_pipe(false)
  local timeout = uv.new_timer()
  timeout:start(5000, 0, function()
    if not pipe:is_closing() then pipe:close() end
    timeout:stop()
    timeout:close()
  end)
  pipe:connect('\\\\.\\pipe\\' .. session.pipe, function(err)
    if err then pipe:close(); vim.schedule(function() vim.notify('WPF 通訊尚未就緒：' .. err, vim.log.levels.WARN) end); return end

    local payload = session.mode == 'designer' and {command='applyXamlText', path=file, xamlText=text}
      or {filePath=file, xamlText=text, previousXamlText=session.previous[file], changeKind='fullFile'}
    pipe:read_start(function(e, data)
      if data and session.mode == 'runtime' then vim.schedule(function() vim.notify('WPF: ' .. data) end) end
      if e or not data then pipe:close() end
    end)
    pipe:write(vim.json.encode(payload) .. '\n', function()
      if session.mode == 'designer' then pipe:shutdown(function() if not pipe:is_closing() then pipe:close() end end) end
    end)
    session.previous[file] = text
  end)
end
function M.start(mode, project, xaml)
  if vim.fn.has('win32') ~= 1 then
    vim.notify('WPF 設計器與執行時熱重載目前僅支援 Windows', vim.log.levels.WARN)
    return
  end
  project = project or require('wpf-assistant.core').startup_project()
  if not project then vim.notify('未找到啟動專案', vim.log.levels.ERROR); return end
  project = vim.fn.fnamemodify(project, ':p')
  if sessions[project] then vim.notify('請先執行 :WpfToolsStop'); return end
  local file = xaml or vim.api.nvim_buf_get_name(0)
  if mode == 'designer' and not file:lower():match('%.xaml$') then vim.notify('請先開啟 WPF XAML'); return end
  vim.notify('正在構建 WPF 專案…')
  run({'dotnet','build',project,'-c','Debug'}, function()
    run({'dotnet','msbuild',project,'-nologo','-getProperty:TargetPath,TargetFramework'}, function(output)
      local ok, result = pcall(vim.json.decode, output)
      if not ok or not result.Properties then vim.notify('無法解析 MSBuild 輸出：' .. output, vim.log.levels.ERROR); return end
      local target = result.Properties.TargetPath
      if not result.Properties.TargetFramework:match('^net%d+%.') then vim.notify('目前 nvim 熱重載接入僅支援現代 .NET WPF', vim.log.levels.ERROR); return end
      local dir = vim.fn.fnamemodify(target, ':h')
      local session = { mode=mode, pipe='nvim-wpf-' .. uv.hrtime(), previous={} }
      local args, env
      if mode == 'designer' then
        env = { NVIM_WPF_ASSEMBLY=target, NVIM_WPF_APP_XAML=vim.fn.fnamemodify(project, ':h') .. '/App.xaml' }
        args = {tools() .. '/designer/Demo.XamlDesigner.exe','--pipe',session.pipe}
        for _, dll in ipairs(vim.fn.globpath(dir, '*.dll', false, true)) do
          if managed_dll(dll) then table.insert(args,dll) end
        end
        table.insert(args, file)
      else
        args = {'dotnet',target}
        local hook = tools() .. '/runtime/WpfHotReload.Runtime.dll'
        local existing = vim.env.DOTNET_STARTUP_HOOKS
        env = {WPF_HOTRELOAD_PIPE=session.pipe, WPF_HOTRELOAD_START_HIDDEN='0', ENABLE_XAML_DIAGNOSTICS_SOURCE_INFO='1', DOTNET_STARTUP_HOOKS=existing and (existing .. ';' .. hook) or hook}
      end
      local binary = mode == 'designer' and args[1] or tools() .. '/runtime/WpfHotReload.Runtime.dll'
      if vim.fn.filereadable(binary) ~= 1 then vim.notify('缺少 WPF 工具：' .. binary, vim.log.levels.ERROR); return end
      session.process = vim.system(args, {cwd=mode == 'designer' and tools() .. '/designer' or dir, env=env, text=true}, vim.schedule_wrap(function(r)
        if sessions[project] == session then sessions[project] = nil end
        if r.code ~= 0 then vim.notify('WPF 已結束：' .. (r.stderr or ''),vim.log.levels.WARN) end
      end))
      sessions[project] = session
      vim.notify('WPF ' .. mode .. ' 已啟動，儲存 XAML 後同步')
    end)
  end)
end
function M.stop()
  for project, session in pairs(sessions) do session.process:kill(15); sessions[project]=nil end
end
local group = vim.api.nvim_create_augroup('WpfLeXtudio', {clear=true})
vim.api.nvim_create_autocmd('BufWritePost', {group=group, pattern='*.xaml', callback=function(ev)
  local file=vim.fn.fnamemodify(ev.file, ':p')
  for project, session in pairs(sessions) do
    local root=vim.fn.fnamemodify(project, ':h'):lower():gsub('\\','/') .. '/'
    if file:lower():gsub('\\','/'):sub(1,#root)==root then send(session,file) end
  end
end})
vim.api.nvim_create_autocmd('VimLeavePre', {group=group, callback=M.stop})
return M
