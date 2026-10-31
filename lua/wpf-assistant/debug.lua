-- WPF Assistant - 调试模块（nvim-dap + netcoredbg）
-- 负责注册 dap 适配器/启动配置、启动与附加调试、以及调试环境自查。
-- 对应 qt-assistant 的 :QtDebug / :QtDebugAttach / :QtDebugStatus / :QtDebugSetup。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local history = require("wpf-assistant.history")
local system = require("wpf-assistant.system")
local ui = require("wpf-assistant.ui")

local ADAPTER = "netcoredbg"

local function dap_module()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return nil, tostring(dap)
  end
  return dap
end

local function current_configuration(root)
  return history.get_pref(root, "configuration") or config.get_value("dotnet.configuration", "Debug")
end

--- 解析启动用的可执行文件：优先 csproj 的真实 TargetPath，退回常规输出路径
--- @return string|nil path, string|nil error
function M.program_path(project, configuration)
  local root = core.project_root()
  configuration = configuration or current_configuration(root)
  project = project or config.get_value("debug.project") or core.startup_project(root)
  if not project then
    return nil, ("没有找到 .csproj（%s）"):format(root)
  end

  local override = config.get_value("debug.program")
  if type(override) == "string" and override ~= "" then
    local resolved = override:gsub("%${configuration}", configuration)
    resolved = resolved:gsub("%${projectDir}", (core.project_dir(project):gsub("%%", "%%%%")))
    return resolved
  end

  local dotnet = system.detect_dotnet()
  if dotnet then
    local result = system.run_sync({
      dotnet,
      "msbuild",
      project,
      "-getProperty:TargetPath",
      "-p:Configuration=" .. configuration,
      "-nologo",
    }, { cwd = core.project_dir(project) })
    if result.ok then
      for _, line in ipairs(vim.split(result.stdout, "\n", { trimempty = true })) do
        local candidate = vim.trim(line)
        if candidate:lower():match("%.dll$") or candidate:lower():match("%.exe$") then
          -- netcoredbg 用 .dll 或 apphost .exe 都可以；同目录有 .exe 时优先，和手动配置的习惯一致
          local apphost = candidate:gsub("%.dll$", ".exe")
          if apphost ~= candidate and system.is_file(apphost) then
            return apphost
          end
          if system.is_file(candidate) then
            return candidate
          end
          -- 已构建产物不存在时也返回路径，便于在状态里提示需要构建
          return candidate
        end
      end
    end
  end

  local fallback = M.conventional_program_path(project, configuration)
  if fallback then
    if system.is_file(fallback) then
      return fallback
    end
    return fallback, ("未找到已构建的输出（%s），先执行 <leader>wb 构建"):format(fallback)
  end
  return nil, "无法推断启动程序路径"
end

--- 常规输出路径（不调用 msbuild，供 :WpfDoctor 等快速场景使用）
--- @return string 预测路径（可能尚未构建）
function M.conventional_program_path(project, configuration)
  project = project or core.startup_project(core.project_root())
  if not project then
    return nil
  end
  configuration = configuration or current_configuration(core.project_root())
  local assembly = core.project_namespace(project)
  local tfm = core.project_target_framework(project) or ""
  local out_dir = vim.fs.joinpath(core.project_dir(project), "bin", configuration, tfm)
  for _, extension in ipairs({ ".exe", ".dll" }) do
    local candidate = vim.fs.joinpath(out_dir, assembly .. extension)
    if system.is_file(candidate) then
      return candidate
    end
  end
  return vim.fs.joinpath(out_dir, assembly .. ".exe")
end

--- 注册 netcoredbg 适配器
local function ensure_adapter()
  local dap, err = dap_module()
  if not dap then
    return nil, "未安装 nvim-dap（LazyVim 的 lang.dotnet extra 已包含）", err
  end
  local adapter_path = config.get_value("debug.adapter_path") or system.detect_debugger()
  if not adapter_path then
    return nil, "未找到 netcoredbg（可用 mason 安装，或配置 debug.adapter_path）"
  end
  dap.adapters = dap.adapters or {}
  dap.adapters[ADAPTER] = {
    type = "executable",
    command = adapter_path,
    args = { "--interpreter=vscode" },
  }
  return dap, nil, adapter_path
end

--- 生成/刷新当前工程的启动配置，返回配置表
--- @return table|nil launch_config, string|nil error
function M.setup()
  if not config.get_value("debug.enabled", true) then
    return nil, "调试功能已在配置中关闭（debug.enabled = false）"
  end
  local dap, err = ensure_adapter()
  if not dap then
    return nil, err
  end

  local root = core.project_root()
  local project = config.get_value("debug.project") or core.startup_project(root)
  local configuration = current_configuration(root)
  local program, program_err = M.program_path(project, configuration)

  local name = ("WPF: %s (%s)"):format(project and vim.fs.basename(project) or "current", configuration)
  local launch = {
    name = name,
    type = ADAPTER,
    request = "launch",
    program = program
      or function()
        return M.program_path()
      end,
    args = config.get_value("debug.args", {}),
    cwd = project and core.project_dir(project) or root,
    stopAtEntry = config.get_value("debug.stop_at_entry", false),
    env = config.get_value("debug.env", {}),
    console = config.get_value("debug.console", "internalConsole"),
    justMyCode = config.get_value("debug.just_my_code", true),
  }

  dap.configurations = dap.configurations or {}
  dap.configurations.cs = dap.configurations.cs or {}
  local kept = {}
  for _, existing in ipairs(dap.configurations.cs) do
    if existing.name ~= name then
      kept[#kept + 1] = existing
    end
  end
  kept[#kept + 1] = launch
  dap.configurations.cs = kept

  M._launch = launch
  M._program_error = program and nil or program_err
  return launch, nil
end

local function launch_or_continue(launch)
  local dap = dap_module()
  if not dap then
    return
  end
  if type(dap.run) == "function" then
    dap.run(launch)
  else
    dap.continue()
  end
end

--- 启动调试（可选先构建）
function M.start()
  local launch, err = M.setup()
  if not launch then
    core.error(tostring(err))
    M.print_hints()
    return
  end

  if not M._program_error then
    launch_or_continue(launch)
    return
  end

  if config.get_value("debug.build_before_debug", true) then
    core.info("尚未构建，先执行构建再启动调试…")
    require("wpf-assistant.build_manager").build(nil, {
      on_success = function()
        local fresh = M.setup()
        if fresh then
          launch_or_continue(fresh)
        end
      end,
    })
    return
  end

  core.error(M._program_error)
end

--- 附加到已运行的进程
function M.attach()
  local dap, err = ensure_adapter()
  if not dap then
    core.error(tostring(err))
    M.print_hints()
    return
  end

  local root = core.project_root()
  local project = core.startup_project(root)
  local assembly = project and vim.fs.basename(project):gsub("%.csproj$", "") or nil

  local candidates = {}
  if assembly then
    vim.list_extend(candidates, M.list_processes({ assembly .. ".exe" }))
  end
  vim.list_extend(candidates, M.list_processes({ "dotnet.exe", "dotnet" }))

  local function attach_to(pid)
    local launch = {
      name = ("WPF: attach %s"):format(assembly or tostring(pid)),
      type = ADAPTER,
      request = "attach",
      processId = pid,
    }
    M._launch = launch
    launch_or_continue(launch)
    core.info(("已附加到进程 %s"):format(tostring(pid)))
  end

  if #candidates == 0 then
    ui.input("进程 PID（未找到候选进程，可手动输入）", "", function(input)
      local pid = tonumber(input)
      if pid then
        attach_to(pid)
      else
        core.error("PID 无效")
      end
    end)
    return
  end

  vim.ui.select(candidates, {
    prompt = "附加到哪个进程：",
    format_item = function(item)
      return ("%s  (PID %d)"):format(item.name, item.pid)
    end,
  }, function(item)
    if item then
      attach_to(item.pid)
    end
  end)
end

--- 列出候选进程
--- @return { pid: integer, name: string }[]
function M.list_processes(patterns)
  local results = {}
  local seen = {}
  if system.is_windows then
    for _, pattern in ipairs(patterns) do
      local result = system.run_sync({ "tasklist", "/FI", "IMAGENAME eq " .. pattern, "/FO", "CSV", "/NH" })
      if result.ok then
        for _, line in ipairs(vim.split(result.stdout, "\n", { trimempty = true })) do
          local name, pid = line:match('^"([^"]+)","(%d+)"')
          if name and pid and not seen[pid] then
            seen[pid] = true
            results[#results + 1] = { pid = tonumber(pid), name = name }
          end
        end
      end
    end
  else
    for _, pattern in ipairs(patterns) do
      local result = system.run_sync({ "pgrep", "-af", pattern })
      if result.ok then
        for _, line in ipairs(vim.split(result.stdout, "\n", { trimempty = true })) do
          local pid, command = line:match("^(%d+)%s+(.*)$")
          if pid and not seen[pid] then
            seen[pid] = true
            results[#results + 1] = { pid = tonumber(pid), name = vim.trim(command):sub(1, 60) }
          end
        end
      end
    end
  end
  return results
end

local function netcoredbg_version(path)
  if not path then
    return nil
  end
  local result = system.run_sync({ path, "--version" })
  local text = vim.trim(result.stdout ~= "" and result.stdout or result.stderr)
  return text ~= "" and text:gsub("\n", " ") or nil
end

--- @return string[] 报告行
function M.report_lines()
  local root = core.project_root()
  local project = core.startup_project(root)
  local configuration = current_configuration(root)
  local adapter_path = config.get_value("debug.adapter_path") or system.detect_debugger()
  local program, program_err = M.program_path(project, configuration)
  local dap, dap_err = dap_module()

  local lines = {
    "# WPF Assistant - 调试状态",
    "",
    ("- nvim-dap：%s"):format(dap and "✓ 已安装" or ("✗ 未安装（" .. tostring(dap_err) .. "）")),
    ("- netcoredbg：%s"):format(adapter_path and ("✓ `" .. adapter_path .. "`") or "✗ 未找到"),
  }
  if adapter_path then
    local version = netcoredbg_version(adapter_path)
    if version then
      lines[#lines + 1] = ("- netcoredbg 版本：%s"):format(version)
    end
  end
  lines[#lines + 1] = ("- 项目根：`%s`"):format(root)
  lines[#lines + 1] = ("- 启动项目：`%s`"):format(project and system.relpath(root, project) or "（未确定）")
  lines[#lines + 1] = ("- 配置：`%s`"):format(configuration)
  lines[#lines + 1] = ("- 启动程序：%s"):format(program and ("`" .. program .. "`") or ("✗ " .. tostring(program_err)))
  if program and not system.is_file(program) then
    lines[#lines + 1] = "  - ⚠ 该文件还不存在，先构建（<leader>wb）或 <leader>wX 会自动先构建"
  end

  if dap then
    dap.configurations = dap.configurations or {}
    local names = {}
    for _, entry in ipairs(dap.configurations.cs or {}) do
      names[#names + 1] = entry.name or "?"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("## dap.configurations.cs（%d 条）"):format(#names)
    lines[#lines + 1] = ""
    for _, name in ipairs(names) do
      lines[#lines + 1] = ("- %s"):format(name)
    end
  end

  return lines
end

function M.hints()
  local hints = {}
  if not system.detect_debugger() then
    hints[#hints + 1] = "安装 netcoredbg：`:Mason` 里安装 netcoredbg，或从 "
      .. "https://github.com/Samsung/netcoredbg 下载后配置 debug.adapter_path"
  end
  if not pcall(require, "dap") then
    hints[#hints + 1] = "安装 nvim-dap（LazyVim 的 lang.dotnet extra 已包含）"
  end
  hints[#hints + 1] = "调试键位：<leader>wX 启动、<leader>wY 附加、<leader>wZ 查看状态；断点用 nvim-dap 默认键位（<leader>db 等）"
  return hints
end

function M.print_hints()
  for _, hint in ipairs(M.hints()) do
    core.info(hint)
  end
end

function M.status()
  local lines = M.report_lines()
  if not system.detect_debugger() or not pcall(require, "dap") then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## 建议"
    lines[#lines + 1] = ""
    for _, hint in ipairs(M.hints()) do
      lines[#lines + 1] = "- " .. hint
    end
  end
  ui.scratch("WpfAssistant://debug", lines)
end

--- 环境准备：注册适配器与配置，并把结论打印出来
function M.setup_debugging()
  local launch, err = M.setup()
  if launch then
    core.info(("调试配置就绪：%s"):format(launch.name))
  else
    core.error(tostring(err))
  end
  M.status()
end

return M
