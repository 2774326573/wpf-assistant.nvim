-- WPF Assistant - 系统/工具链模块
-- 负责平台判断、可执行文件探测、同步命令执行，以及 dotnet / 调试器 探测。

local M = {}

local uv = vim.uv

M.is_windows = uv.os_uname().sysname:lower():find("windows") ~= nil

--- @return string "windows" | "linux" | "macos" | "unknown"
function M.os()
  local sysname = uv.os_uname().sysname:lower()
  if sysname:find("windows") then
    return "windows"
  elseif sysname:find("darwin") then
    return "macos"
  elseif sysname:find("linux") then
    return "linux"
  end
  return "unknown"
end

--- @return boolean
function M.exists(path)
  return type(path) == "string" and path ~= "" and uv.fs_stat(path) ~= nil
end

function M.is_dir(path)
  local stat = type(path) == "string" and uv.fs_stat(path) or nil
  return stat ~= nil and stat.type == "directory"
end

function M.is_file(path)
  local stat = type(path) == "string" and uv.fs_stat(path) or nil
  return stat ~= nil and stat.type == "file"
end

--- 探测命令：绝对路径看文件是否存在，裸名字查 PATH
--- @return string|nil
function M.executable(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if name:find("[/\\]") then
    return M.exists(name) and name or nil
  end
  local path = vim.fn.exepath(name)
  return path ~= "" and path or nil
end

--- 同步执行命令（用于 dotnet new / --version 等需要立刻拿到结果的场景）
--- @param args string[]
--- @param opts? { cwd?: string }
--- @return { code: integer, stdout: string, stderr: string, ok: boolean }
function M.run_sync(args, opts)
  opts = opts or {}
  local ok, result = pcall(vim.system, args, { cwd = opts.cwd, text = true }, nil)
  if not ok or type(result) ~= "table" then
    return { code = -1, stdout = "", stderr = tostring(result), ok = false }
  end
  local waited = result:wait()
  local code = waited.code or -1
  return {
    code = code,
    stdout = waited.stdout or "",
    stderr = waited.stderr or "",
    ok = code == 0,
  }
end

--- @return string|nil
function M.detect_dotnet()
  return M.executable("dotnet")
end

--- @return string|nil
function M.dotnet_version(dotnet)
  dotnet = dotnet or M.detect_dotnet()
  if not dotnet then
    return nil
  end
  local result = M.run_sync({ dotnet, "--version" })
  if not result.ok then
    return nil
  end
  return vim.trim(result.stdout)
end

--- @return { version: string, path: string }[]
function M.list_sdks(dotnet)
  dotnet = dotnet or M.detect_dotnet()
  if not dotnet then
    return {}
  end
  local result = M.run_sync({ dotnet, "--list-sdks" })
  if not result.ok then
    return {}
  end
  local sdks = {}
  for _, line in ipairs(vim.split(result.stdout, "\n", { trimempty = true })) do
    local version, path = line:match("^(%S+)%s+%[(.+)%]$")
    if version then
      sdks[#sdks + 1] = { version = version, path = path }
    end
  end
  return sdks
end

--- @return string[]
function M.list_runtimes(dotnet)
  dotnet = dotnet or M.detect_dotnet()
  if not dotnet then
    return {}
  end
  local result = M.run_sync({ dotnet, "--list-runtimes" })
  if not result.ok then
    return {}
  end
  local runtimes = {}
  for _, line in ipairs(vim.split(result.stdout, "\n", { trimempty = true })) do
    runtimes[#runtimes + 1] = line
  end
  return runtimes
end

--- 探测 .NET 调试器（netcoredbg / vsdbg）
--- @return string|nil
function M.detect_debugger()
  local candidates = {
    vim.g.netcoredbg_path,
    "netcoredbg",
    vim.fn.expand("~/netcoredbg/netcoredbg.exe"),
    "C:/netcoredbg/netcoredbg.exe",
    "D:/install/netcoredbg/netcoredbg.exe",
  }
  for _, candidate in ipairs(candidates) do
    local path = M.executable(candidate)
    if path then
      return path
    end
  end
  -- Mason 安装的 netcoredbg
  local mason = vim.fn.stdpath("data") .. "/mason/packages/netcoredbg"
  if M.is_dir(mason) then
    local found = vim.fs.find(function(name)
      return name:lower() == "netcoredbg.exe" or name == "netcoredbg"
    end, { path = mason, type = "file", limit = 1 })
    if found[1] then
      return found[1]
    end
  end
  return nil
end

--- 常用的全局 .NET 工具（格式化/样式）
function M.detect_dotnet_tools()
  return {
    csharpier = M.executable("csharpier"),
    xstyler = M.executable("xstyler"),
    dotnet_format = M.executable("dotnet") ~= nil,
  }
end

--- 写文件（LF、UTF-8、自动建目录）
--- @return boolean, string|nil
function M.write_file(path, text)
  local dir = vim.fs.dirname(path)
  if dir and dir ~= "" and not M.is_dir(dir) then
    local ok = pcall(vim.fn.mkdir, dir, "p")
    if not ok and not M.is_dir(dir) then
      return false, ("无法创建目录：%s"):format(dir)
    end
  end
  local handle, err = io.open(path, "wb")
  if not handle then
    return false, tostring(err)
  end
  handle:write((text:gsub("\r\n", "\n")))
  handle:close()
  return true, nil
end

--- @return string[]
function M.read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end
  return lines
end

--- 相对路径显示（同盘符优先，失败时退回绝对路径）
function M.relpath(base, target)
  return vim.fs.relpath(base, target) or target
end

return M
