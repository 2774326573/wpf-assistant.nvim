-- WPF Assistant - LSP 支持模块
-- 探测 C# 语言服务器（OmniSharp / csharp-ls / roslyn）、检查已挂载的客户端，
-- 并确保还原出 OmniSharp/roslyn 依赖的 obj/project.assets.json（对应 qt 的 compile_commands.json）。

local M = {}

local core = require("wpf-assistant.core")
local system = require("wpf-assistant.system")
local ui = require("wpf-assistant.ui")

local MASON = vim.fn.stdpath("data") .. "/mason/packages"

local function find_executable_in(dir, names)
  if not system.is_dir(dir) then
    return nil
  end
  local lowered = {}
  for _, name in ipairs(names) do
    lowered[name:lower()] = true
  end
  local found = vim.fs.find(function(name)
    local lower = name:lower()
    return lowered[lower] or lowered[(lower:gsub("%.exe$", ""))]
  end, { path = dir, type = "file", limit = 1 })
  return found[1]
end

--- 已安装的 C# 语言服务器
--- @return { name: string, path: string|nil, source: string }[]
function M.servers()
  local candidates = {
    {
      name = "omnisharp",
      bins = { "omnisharp", "OmniSharp", "omnisharp.exe", "OmniSharp.exe" },
      mason = MASON .. "/omnisharp",
    },
    {
      name = "csharp_ls",
      bins = { "csharp-ls", "csharp-ls.exe" },
      mason = MASON .. "/csharp-ls",
    },
    {
      name = "roslyn_ls",
      bins = { "roslyn-language-server", "roslyn-language-server.exe" },
      mason = MASON .. "/roslyn-language-server",
    },
  }

  local result = {}
  for _, candidate in ipairs(candidates) do
    local path, source
    for _, bin in ipairs(candidate.bins) do
      local resolved = system.executable(bin)
      if resolved then
        path, source = resolved, "PATH"
        break
      end
    end
    if not path then
      local mason_path = find_executable_in(candidate.mason, candidate.bins)
      if mason_path then
        path, source = mason_path, "mason"
      end
    end
    result[#result + 1] = { name = candidate.name, path = path, source = source or "-" }
  end
  return result
end

--- 当前缓冲区上挂载的 C# 客户端
--- @return string[]
function M.clients(bufnr)
  bufnr = bufnr or 0
  local names = {}
  local ok, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
  if not ok or type(clients) ~= "table" then
    return names
  end
  for _, client in ipairs(clients) do
    if client.name then
      names[#names + 1] = client.name
    end
  end
  return names
end

--- OmniSharp/roslyn 需要的还原产物
function M.assets_path(project)
  if not project then
    return nil
  end
  return vim.fs.joinpath(vim.fs.dirname(project), "obj", "project.assets.json")
end

--- @return boolean 是否已还原
function M.has_assets(project)
  local path = M.assets_path(project)
  return path ~= nil and system.is_file(path)
end

--- 运行 dotnet restore（生成 project.assets.json）
function M.restore()
  local build_manager = require("wpf-assistant.build_manager")
  build_manager.restore()
end

--- 若缺少还原产物，提示并（可选）自动还原
--- @return boolean 已就绪
function M.ensure_assets(project, opts)
  opts = opts or {}
  project = project or core.startup_project(core.project_root())
  if not project then
    return false
  end
  if M.has_assets(project) then
    return true
  end
  if opts.auto then
    core.warn(("缺少 %s，正在执行 dotnet restore…"):format(core.relpath(core.project_root(), M.assets_path(project))))
    M.restore()
    return false
  end
  core.warn(
    ("尚未还原依赖（缺少 obj/project.assets.json）——语言服务器可能无法解析工程；运行 `:WpfRestore` 或 <leader>wR")
  )
  return false
end

--- @return string[] 报告行
function M.report_lines()
  local root = core.project_root()
  local project = core.startup_project(root)
  local lines = {
    "# WPF Assistant - C# 语言服务器状态",
    "",
    ("- 项目根：`%s`"):format(root),
    ("- 启动项目：`%s`"):format(project and system.relpath(root, project) or "（未确定）"),
    "",
    "## 已安装的服务器",
    "",
    "| 服务器 | 状态 | 路径 | 来源 |",
    "| --- | --- | --- | --- |",
  }
  local installed = 0
  for _, server in ipairs(M.servers()) do
    local ok = server.path ~= nil
    if ok then
      installed = installed + 1
    end
    lines[#lines + 1] = ("| `%s` | %s | `%s` | %s |"):format(
      server.name,
      ok and "✓" or "✗",
      server.path or "-",
      server.source
    )
  end

  local clients = M.clients(0)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## 当前缓冲区"
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("- 文件：`%s`"):format(vim.api.nvim_buf_get_name(0))
  lines[#lines + 1] = ("- 已挂载客户端：%s"):format(#clients > 0 and table.concat(clients, ", ") or "（无）")

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## 还原产物"
  lines[#lines + 1] = ""
  if project then
    local assets = M.assets_path(project)
    lines[#lines + 1] = ("- `obj/project.assets.json`：%s"):format(M.has_assets(project) and "✓ 已生成" or "✗ 缺失")
    lines[#lines + 1] = ("  路径：`%s`"):format(assets or "-")
  else
    lines[#lines + 1] = "- 没有找到 .csproj，无法判断还原状态"
  end

  if installed == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## 建议"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "- 安装 OmniSharp：`dotnet tool install -g omnisharp`（或 `:Mason` 安装 omnisharp / csharp-ls）"
    lines[#lines + 1] = "- LazyVim 的 `lang.dotnet` extra 已包含 OmniSharp 配置，装上服务器即可生效"
  end
  return lines
end

function M.info()
  ui.scratch("WpfAssistant://lsp", M.report_lines())
end

return M
