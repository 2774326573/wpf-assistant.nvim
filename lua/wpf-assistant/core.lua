-- WPF Assistant - 核心模块
-- 项目/解决方案定位、按扩展名查找文件、命名空间与目标框架读取、终端任务执行。
--
-- 注意：vim.fs.find()/vim.fs.root() 对 string/table 形式的 names 只做精确 basename 匹配，
-- 不支持 "*.csproj" 这类通配符（见 :help vim.fs.find），因此这里统一用函数谓词匹配扩展名。

local M = {}

local config = require("wpf-assistant.config")
local history = require("wpf-assistant.history")
local system = require("wpf-assistant.system")

-- 遍历项目时跳过的目录（构建产物/依赖/版本控制）
M.skip_dirs = {
  ".git",
  ".vs",
  ".vscode",
  ".idea",
  ".zcode",
  "bin",
  "obj",
  "node_modules",
  "packages",
  "TestResults",
  ".venv",
}

--- 生成按扩展名匹配的谓词，供 vim.fs.find / vim.fs.root 使用
--- @param extensions string[] 不含点的扩展名，大小写不敏感
function M.extension_matcher(extensions)
  local lowered = {}
  for _, ext in ipairs(extensions) do
    lowered[#lowered + 1] = ext:lower()
  end
  return function(name)
    local ext = name:match("%.([^./\\]+)$")
    return ext ~= nil and vim.tbl_contains(lowered, ext:lower())
  end
end

--- 递归查找指定扩展名的文件（绝对路径）
--- @param root string
--- @param extensions string[]
--- @param opts? { limit?: number, skip?: string[] }
--- @return string[]
function M.find_by_extension(root, extensions, opts)
  opts = opts or {}
  if not system.is_dir(root) then
    return {}
  end
  local matcher = M.extension_matcher(extensions)
  local limit = opts.limit or math.huge
  local skip = opts.skip or M.skip_dirs
  local found = {}
  local iterator = vim.fs.dir(root, {
    depth = math.huge,
    skip = function(dir)
      return not vim.tbl_contains(skip, vim.fs.basename(dir))
    end,
  })
  for name, type_ in iterator do
    if type_ == "file" and matcher(vim.fs.basename(name)) then
      found[#found + 1] = vim.fs.joinpath(root, name)
      if #found >= limit then
        break
      end
    end
  end
  table.sort(found)
  return found
end

--- @return string|nil
function M.first_by_extension(root, extensions, opts)
  local found = M.find_by_extension(root, extensions, vim.tbl_extend("force", opts or {}, { limit = 1 }))
  return found[1]
end

local function root_source()
  local file = vim.api.nvim_buf_get_name(0)
  if file ~= "" and vim.bo.buftype == "" then
    return file
  end
  return vim.fn.getcwd()
end

--- 当前项目根目录：优先解决方案所在目录，其次最近的 .csproj 目录，最后退回 cwd
--- @return string
function M.project_root()
  -- 任务终端缓冲区会记录启动时的工作目录，避免在终端里再按快捷键时解析错误
  local buffer = vim.api.nvim_get_current_buf()
  local cached = vim.b[buffer].wpf_assistant_root
  if type(cached) == "string" and system.is_dir(cached) then
    return cached
  end

  local source = root_source()
  return vim.fs.root(source, M.extension_matcher({ "sln", "slnx" }))
    or vim.fs.root(source, M.extension_matcher({ "csproj" }))
    or vim.fn.getcwd()
end

--- 项目内所有 .csproj（已跳过 bin/obj 等目录）
--- @return string[]
function M.projects(root, limit)
  return M.find_by_extension(root or M.project_root(), { "csproj" }, { limit = limit })
end

--- @return string|nil
function M.solution(root)
  return M.first_by_extension(root or M.project_root(), { "sln", "slnx" })
end

--- 解析 .sln（经典格式）与 .slnx（XML 格式）中登记的项目路径
--- @return string[]
function M.solution_projects(sln)
  if not system.is_file(sln) then
    return {}
  end
  local dir = vim.fs.dirname(sln)
  local projects = {}
  local seen = {}

  local function add(rel)
    if not rel or not rel:lower():match("%.csproj$") then
      return
    end
    local path = vim.fs.normalize(vim.fs.joinpath(dir, (rel:gsub("\\", "/"))))
    if system.is_file(path) and not seen[path:lower()] then
      seen[path:lower()] = true
      projects[#projects + 1] = path
    end
  end

  local is_xml = sln:lower():match("%.slnx$") ~= nil
  for _, line in ipairs(system.read_lines(sln)) do
    if is_xml then
      for rel in line:gmatch('<Project[^>]-Path="([^"]+)"') do
        add(rel)
      end
    else
      -- 经典 .sln 格式：Project("{类型 GUID}") = "名字", "相对路径.csproj", "{项目 GUID}"
      add(line:match('^%s*Project%(%s*"{[^}]*}"%s*%)%s*=%s*"[^"]*"%s*,%s*"([^"]+)"'))
    end
  end
  return projects
end

--- 启动项目：记录过的偏好 → 解决方案中的第一个项目 → 唯一的项目 → 第一个 .csproj
--- @return string|nil
function M.startup_project(root)
  root = root or M.project_root()
  local projects = M.projects(root)

  local pref = history.get_pref(root, "startup_project")
  if type(pref) == "string" and system.is_file(pref) then
    return pref
  end

  local sln = M.solution(root)
  if sln then
    local from_solution = M.solution_projects(sln)
    if from_solution[1] then
      return from_solution[1]
    end
  end

  return projects[1]
end

--- 构建目标：解决方案或单个项目
--- @param root string|nil
--- @param mode? string 覆盖配置里的 build.target_mode
--- @return string|nil target, string|nil kind "solution" | "project"
function M.build_target(root, mode)
  root = root or M.project_root()
  mode = mode or config.get_value("build.target_mode", "auto")

  if mode == "solution" then
    local sln = M.solution(root)
    return sln, sln and "solution" or nil
  elseif mode == "project" then
    local project = M.startup_project(root)
    return project, project and "project" or nil
  end

  local pref = history.get_pref(root, "build_target")
  if type(pref) == "string" and system.is_file(pref) then
    local lower = pref:lower()
    local is_solution = lower:match("%.sln$") ~= nil or lower:match("%.slnx$") ~= nil
    return pref, is_solution and "solution" or "project"
  end

  local sln = M.solution(root)
  if sln then
    return sln, "solution"
  end
  local project = M.startup_project(root)
  return project, project and "project" or nil
end

--- 读取 .csproj 的根命名空间（没有则用程序集名，再退回文件名）
--- @return string
function M.project_namespace(project)
  local fallback = vim.fs.basename(project or ""):gsub("%.csproj$", "")
  if fallback == "" then
    fallback = config.get_value("namespace_fallback", "App")
  end
  if not system.is_file(project) then
    return fallback
  end
  local content = table.concat(system.read_lines(project), "\n")
  local namespace = content:match("<RootNamespace>%s*([^<%s]+)%s*</RootNamespace>")
    or content:match("<AssemblyName>%s*([^<%s]+)%s*</AssemblyName>")
  return namespace or fallback
end

--- @return string|nil
function M.project_target_framework(project)
  if not system.is_file(project) then
    return nil
  end
  local content = table.concat(system.read_lines(project), "\n")
  return content:match("<TargetFramework>%s*([^<%s]+)%s*</TargetFramework>")
    or content:match("<TargetFrameworks>%s*([^<%s]+)%s*</TargetFrameworks>")
end

--- SDK 风格工程（新式 .csproj）会隐式包含 .cs/.xaml，不需要手动登记文件
--- @return boolean
function M.is_sdk_style(project)
  if not system.is_file(project) then
    return true
  end
  for i, line in ipairs(system.read_lines(project)) do
    if i > 20 then
      break
    end
    if line:match("<Project") then
      return line:match("Sdk%s*=") ~= nil
    end
  end
  return true
end

--- 项目内与某个文件配套的输出目录等（预留：dotnet build 的输出路径）
--- @return string
function M.project_dir(project)
  return vim.fs.dirname(project) or M.project_root()
end

function M.relpath(base, target)
  return system.relpath(base, target)
end

-- ==================== 通知 ====================

local function notify(message, level)
  vim.notify("WPF Assistant: " .. message, level or vim.log.levels.INFO)
end

function M.info(message)
  notify(message, vim.log.levels.INFO)
end

function M.warn(message)
  notify(message, vim.log.levels.WARN)
end

function M.error(message)
  notify(message, vim.log.levels.ERROR)
end

-- ==================== 终端任务 ====================

--- 在底部开一个分栏（高度自适应，窗口太小时退回普通分栏）
function M.open_split(height)
  height = math.max(5, math.min(height or 15, (vim.o.lines or 24) - 4))
  local ok = pcall(vim.cmd, ("botright %dsplit"):format(height))
  if not ok then
    pcall(vim.cmd, "botright split")
  end
end

--- 把参数列表格式化成可读命令（用于展示/历史记录）
function M.format_command(args)
  local parts = {}
  for _, arg in ipairs(args) do
    if arg:find("%s") then
      parts[#parts + 1] = '"' .. arg .. '"'
    else
      parts[#parts + 1] = arg
    end
  end
  return table.concat(parts, " ")
end

--- 在底部终端分栏里异步执行命令
--- @param args string[]
--- @param title string 终端缓冲区标题（WpfAssistant://<title>）
--- @param root? string 工作目录，默认当前项目根
--- @param opts? table 可选：kind / configuration / target / record / on_exit(code)
function M.run_in_terminal(args, title, root, opts)
  opts = opts or {}
  root = root or M.project_root()

  local buffer
  if opts.buffer_name ~= false then
    M.open_split(config.get_value("build.terminal.height", 15))
    buffer = vim.api.nvim_get_current_buf()
    pcall(vim.api.nvim_buf_set_name, buffer, "WpfAssistant://" .. title)
    vim.bo.buflisted = false
    vim.b[buffer].wpf_assistant_root = root
  end

  if opts.record ~= false then
    history.add({
      root = root,
      title = title,
      args = args,
      kind = opts.kind,
      configuration = opts.configuration,
      target = opts.target,
    })
  end

  local job = vim.fn.jobstart(args, {
    cwd = root,
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        local ok = code == 0
        local level = ok and vim.log.levels.INFO or vim.log.levels.ERROR
        notify(("%s（%s）"):format(title, ok and "完成" or ("退出码 " .. code)), level)
        if opts.on_exit then
          opts.on_exit(code)
        end
      end)
    end,
  })
  if job <= 0 then
    M.error(("无法启动命令：%s"):format(M.format_command(args)))
    return nil
  end
  return job
end

--- 终端里再跑一遍历史命令（不重复写历史）
function M.rerun(entry)
  if type(entry) ~= "table" or type(entry.args) ~= "table" then
    return
  end
  local root = entry.root or M.project_root()
  if not system.is_dir(root) then
    M.error(("历史命令的项目目录已不存在：%s"):format(tostring(root)))
    return
  end
  M.run_in_terminal(entry.args, entry.title or "rerun", root, { record = false, kind = entry.kind })
end

return M
