-- WPF Assistant - 环境诊断
-- 汇总 .NET/WPF 开发环境信息与缺失项建议（对应 qt-assistant 的 :QtDoctor）。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local history = require("wpf-assistant.history")
local system = require("wpf-assistant.system")
local ui = require("wpf-assistant.ui")

local function mark(ok)
  return ok and "✓" or "✗"
end

--- @return string[] lines
function M.collect()
  local root = core.project_root()
  local dotnet = system.detect_dotnet()
  local version = system.dotnet_version(dotnet)
  local sdks = system.list_sdks(dotnet)
  local designer = config.designer_path()
  local debugger = system.detect_debugger()
  local tools = system.detect_dotnet_tools()
  local sln = core.solution(root)
  local projects = core.projects(root)
  local xaml_files = require("wpf-assistant.file_manager").xaml_files(root)
  local target, kind = core.build_target(root)
  local startup = core.startup_project(root)
  local state = history.summary()

  local lines = {
    "# WpfDoctor - 环境诊断",
    "",
    ("- 平台：`%s`，Neovim `%s`"):format(system.os(), vim.inspect(vim.version()):gsub("[%s{}]", ""):sub(1, 40)),
    ("- 项目根目录：`%s`"):format(root),
    ("- 解决方案：`%s`"):format(sln and system.relpath(root, sln) or "（无）"),
    ("- 启动项目：`%s`"):format(startup and system.relpath(root, startup) or "（未确定）"),
    ("- 构建目标：`%s`（%s）"):format(target and system.relpath(root, target) or "（无）", kind or "-"),
    ("- 构建配置：`%s`"):format(
      history.get_pref(root, "configuration") or config.get_value("dotnet.configuration", "Debug")
    ),
    ("- .csproj 数量：%d，XAML 数量：%d"):format(#projects, #xaml_files),
    "",
    "## 工具链",
    "",
    ("- %s dotnet CLI：`%s`%s"):format(
      mark(dotnet ~= nil),
      dotnet or "未找到",
      version and ("（版本 " .. version .. "）") or ""
    ),
    ("- %s .NET SDK：%d 个"):format(mark(#sdks > 0), #sdks),
  }

  for index, sdk in ipairs(sdks) do
    if index > 5 then
      lines[#lines + 1] = ("    - … 另有 %d 个"):format(#sdks - 5)
      break
    end
    lines[#lines + 1] = ("    - %s  `%s`"):format(sdk.version, sdk.path)
  end

  lines[#lines + 1] = ("- %s XAML 设计器：`%s`"):format(mark(designer ~= nil), designer or "未找到（可选）")
  lines[#lines + 1] = ("- %s :XamlDesigner 命令：%s"):format(
    mark(vim.fn.exists(":XamlDesigner") == 2),
    vim.fn.exists(":XamlDesigner") == 2 and "已由其他配置提供" or "未定义（插件将自行拉起）"
  )
  lines[#lines + 1] = ("- %s netcoredbg 调试器：`%s`"):format(mark(debugger ~= nil), debugger or "未找到（调试可选）")
  lines[#lines + 1] = ("- %s csharpier：`%s`"):format(mark(tools.csharpier ~= nil), tools.csharpier or "未安装")
  lines[#lines + 1] = ("- %s XamlStyler(xstyler)：`%s`"):format(mark(tools.xstyler ~= nil), tools.xstyler or "未安装")
  lines[#lines + 1] = ("- 任务历史：`%s`（%d 个项目）"):format(state.path, state.projects)

  -- 调试（nvim-dap + netcoredbg）：只做快速检查，精确的 TargetPath 用 <leader>wZ 看
  local ok_dap = pcall(require, "dap")
  local adapter_path = config.get_value("debug.adapter_path") or debugger
  local ok_debug, debug = pcall(require, "wpf-assistant.debug")
  local predicted = ok_debug and debug.conventional_program_path(startup) or nil
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## 调试（nvim-dap + netcoredbg）"
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("- %s nvim-dap：%s"):format(mark(ok_dap), ok_dap and "已安装" or "未安装")
  lines[#lines + 1] = ("- %s 调试适配器：`%s`"):format(mark(adapter_path ~= nil), adapter_path or "未找到（可选）")
  lines[#lines + 1] = ("- %s 预测启动程序：`%s`"):format(
    mark(predicted ~= nil and system.is_file(predicted)),
    predicted or "（需先构建）"
  )
  lines[#lines + 1] = "  - 精确路径：`<leader>wZ` / `:WpfDebugStatus`（走 msbuild -getProperty:TargetPath）"

  -- C# 语言服务器
  local ok_lsp, lsp = pcall(require, "wpf-assistant.lsp")
  if ok_lsp then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## C# 语言服务器"
    lines[#lines + 1] = ""
    local installed = {}
    for _, server in ipairs(lsp.servers()) do
      if server.path then
        installed[#installed + 1] = ("`%s`（%s）"):format(server.name, server.source)
      end
    end
    lines[#lines + 1] = ("- %s 已安装：%s"):format(
      mark(#installed > 0),
      #installed > 0 and table.concat(installed, "、") or "未找到（`:Mason` 安装 omnisharp / csharp-ls）"
    )
    lines[#lines + 1] = ("- %s obj/project.assets.json：%s"):format(
      mark(lsp.has_assets(startup)),
      lsp.has_assets(startup) and "已生成" or "缺失（<leader>wR 还原）"
    )
    local clients = lsp.clients(0)
    if #clients > 0 then
      lines[#lines + 1] = ("- 当前缓冲区已挂载：%s"):format(table.concat(clients, ", "))
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## 配置摘要"
  lines[#lines + 1] = ""
  local cfg = config.get()
  lines[#lines + 1] = ("- build.target_mode = `%s`"):format(cfg.build.target_mode)
  lines[#lines + 1] = ("- build.publish = `%s` / self-contained=%s / 输出 `%s`"):format(
    cfg.build.publish.runtime,
    tostring(cfg.build.publish.self_contained),
    cfg.build.publish.output
  )
  lines[#lines + 1] = ("- new_file.register_in_project = `%s`"):format(
    tostring(cfg.new_file.register_in_project)
  )
  lines[#lines + 1] = ("- keymaps = `%s`（preset %s）"):format(cfg.keymaps.prefix, cfg.keymaps.preset)

  local hints = {}
  if not dotnet then
    hints[#hints + 1] = "安装 .NET SDK：https://dotnet.microsoft.com/download"
  end
  if not designer then
    hints[#hints + 1] = "可选：把独立 XAML 设计器路径配到 `designer.path` 或 `vim.g.wpf_designer_exe`"
  end
  if not debugger then
    hints[#hints + 1] = "可选：安装 netcoredbg 后用 nvim-dap 调试（`dotnet tool` 或 https://github.com/Samsung/netcoredbg）"
  end
  if #projects == 0 then
    hints[#hints + 1] = "当前目录不是 .NET 工程：可用 `<leader>wN` 新建，或把 nvim 的 cwd 切到工程目录"
  end
  if ok_lsp then
    local has_server = false
    for _, server in ipairs(lsp.servers()) do
      if server.path then
        has_server = true
        break
      end
    end
    if not has_server then
      hints[#hints + 1] = "安装 C# 语言服务器：`:Mason` 安装 omnisharp 或 csharp-ls"
    end
    if not lsp.has_assets(startup) then
      hints[#hints + 1] = "依赖尚未还原：`<leader>wR`（或 `:WpfLspRestore`）生成 obj/project.assets.json"
    end
  end
  if #hints > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## 建议"
    lines[#lines + 1] = ""
    for _, hint in ipairs(hints) do
      lines[#lines + 1] = "- " .. hint
    end
  end

  return lines
end

function M.show()
  local lines = M.collect()
  ui.scratch("WpfAssistant://doctor", lines)
  ui.info("环境诊断已生成（dotnet / 设计器 / 调试器 / 工程状态）")
end

return M
