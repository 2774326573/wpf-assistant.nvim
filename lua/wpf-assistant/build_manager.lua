-- WPF Assistant - 构建模块
-- 组装并执行 dotnet 任务（restore/build/run/watch/publish/clean/format/test/pack），
-- 负责构建目标与 Debug/Release 的选择与记忆。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local history = require("wpf-assistant.history")
local system = require("wpf-assistant.system")
local ui = require("wpf-assistant.ui")

--- 当前构建上下文
--- @class WpfBuildContext
--- @field root string 项目根目录
--- @field target string|nil 构建目标（.sln/.slnx/.csproj）
--- @field kind string|nil "solution" 或 "project"
--- @field project string|nil 启动项目（.csproj）
--- @field configuration string Debug/Release 等
--- @field dotnet string dotnet 可执行文件
--- @return WpfBuildContext
function M.context()
  local root = core.project_root()
  local target, kind = core.build_target(root)
  return {
    root = root,
    target = target,
    kind = kind,
    project = core.startup_project(root),
    configuration = history.get_pref(root, "configuration") or config.get_value("dotnet.configuration", "Debug"),
    dotnet = system.detect_dotnet() or config.get_value("dotnet.exe", "dotnet"),
  }
end

function M.target_label(ctx)
  if not ctx.target then
    return "（无）"
  end
  return system.relpath(ctx.root, ctx.target)
end

local function require_target(ctx)
  if not ctx.target then
    core.error(("没有找到 .sln/.slnx/.csproj（%s），可用 <leader>wN 新建工程"):format(ctx.root))
    return false
  end
  if not system.detect_dotnet() then
    core.error("未找到 dotnet CLI，请检查 PATH")
    return false
  end
  return true
end

local function require_project(ctx)
  if not ctx.project then
    core.error(("没有找到可运行的 .csproj（%s），可用 <leader>wS 指定启动项目"):format(ctx.root))
    return false
  end
  if not system.detect_dotnet() then
    core.error("未找到 dotnet CLI，请检查 PATH")
    return false
  end
  return true
end

local function run(ctx, args, title, opts)
  opts = opts or {}
  return core.run_in_terminal(args, title, ctx.root, vim.tbl_extend("force", {
    target = ctx.target,
    configuration = ctx.configuration,
  }, opts))
end

function M.restore()
  local ctx = M.context()
  if not require_target(ctx) then
    return
  end
  run(ctx, { ctx.dotnet, "restore", ctx.target }, "restore", { kind = "restore" })
end

--- @param configuration? string 默认用当前配置
--- @param opts? { run_after?: boolean }
function M.build(configuration, opts)
  opts = opts or {}
  local ctx = M.context()
  local conf = configuration or ctx.configuration
  if not require_target(ctx) then
    return
  end
  local on_exit
  if opts.run_after or opts.on_success then
    on_exit = function(code)
      if code == 0 then
        if opts.on_success then
          opts.on_success()
        end
        if opts.run_after then
          M.run()
        end
      end
    end
  end
  run(ctx, { ctx.dotnet, "build", ctx.target, "-c", conf }, "build-" .. conf, {
    kind = "build",
    configuration = conf,
    on_exit = on_exit,
  })
end

function M.build_release()
  M.build("Release")
end

function M.build_and_run()
  M.build(nil, { run_after = true })
end

function M.run()
  local ctx = M.context()
  if not require_project(ctx) then
    return
  end
  run(ctx, { ctx.dotnet, "run", "--project", ctx.project, "-c", ctx.configuration }, "run", { kind = "run" })
end

function M.watch()
  local ctx = M.context()
  if not require_project(ctx) then
    return
  end
  run(ctx, { ctx.dotnet, "watch", "--project", ctx.project, "-c", ctx.configuration }, "watch", { kind = "watch" })
end

function M.publish()
  local ctx = M.context()
  if not require_project(ctx) then
    return
  end
  local runtime = config.get_value("build.publish.runtime", "win-x64")
  local self_contained = config.get_value("build.publish.self_contained", false)
  local output = config.get_value("build.publish.output", "build/publish")
  local output_dir = output:match("^%a:[/\\]") and output or vim.fs.joinpath(ctx.root, output)

  run(ctx, {
    ctx.dotnet,
    "publish",
    ctx.project,
    "-c",
    "Release",
    "-r",
    runtime,
    "--self-contained",
    self_contained and "true" or "false",
    "-o",
    output_dir,
  }, "publish-" .. runtime, { kind = "publish", configuration = "Release" })
end

function M.clean()
  local ctx = M.context()
  if not require_target(ctx) then
    return
  end
  run(ctx, { ctx.dotnet, "clean", ctx.target }, "clean", { kind = "clean" })
end

function M.format()
  local ctx = M.context()
  if not require_target(ctx) then
    return
  end
  run(ctx, { ctx.dotnet, "format", ctx.target }, "format", { kind = "format" })
end

function M.test()
  local ctx = M.context()
  if not require_target(ctx) then
    return
  end
  run(ctx, { ctx.dotnet, "test", ctx.target }, "test", { kind = "test" })
end

function M.pack()
  local ctx = M.context()
  if not require_project(ctx) then
    return
  end
  run(ctx, { ctx.dotnet, "pack", ctx.project, "-c", "Release" }, "pack", {
    kind = "pack",
    configuration = "Release",
  })
end

--- 选择构建目标（解决方案或某个 .csproj），按项目根记忆
function M.select_target()
  local root = core.project_root()
  local candidates = core.find_by_extension(root, { "sln", "slnx", "csproj" })
  if #candidates == 0 then
    core.error(("没有找到 .sln/.slnx/.csproj（%s）"):format(root))
    return
  end
  local current = core.build_target(root)
  ui.select(candidates, {
    prompt = "选择构建目标（build/clean/format/test）：",
    root = root,
    current = current,
  }, function(target)
    history.set_pref(root, "build_target", target)
    core.info(("构建目标已设为：%s"):format(system.relpath(root, target)))
  end)
end

--- 切换 Debug/Release（也可输入自定义配置，如 Debug-x64）
function M.select_configuration()
  local root = core.project_root()
  local current = history.get_pref(root, "configuration") or config.get_value("dotnet.configuration", "Debug")
  local choices = { "Debug", "Release", "自定义…" }
  ui.select(choices, { prompt = "构建配置（当前 " .. current .. "）：", current = current }, function(choice)
    if choice == "自定义…" then
      ui.input("构建配置", current, function(value)
        history.set_pref(root, "configuration", value)
        core.info(("构建配置已设为：%s"):format(value))
      end)
      return
    end
    history.set_pref(root, "configuration", choice)
    core.info(("构建配置已设为：%s"):format(choice))
  end)
end

local function relative_time(timestamp)
  if type(timestamp) ~= "number" then
    return ""
  end
  local delta = os.time() - timestamp
  if delta < 60 then
    return "刚刚"
  elseif delta < 3600 then
    return ("%d 分钟前"):format(delta / 60)
  elseif delta < 86400 then
    return ("%d 小时前"):format(delta / 3600)
  end
  return os.date("%m-%d %H:%M", timestamp)
end

--- 最近任务：选择后原样重跑
function M.show_history()
  local root = core.project_root()
  local entries = history.list(root)
  if #entries == 0 then
    core.info("还没有任务历史")
    return
  end
  local labels = {}
  local by_label = {}
  for _, entry in ipairs(entries) do
    local label = ("%s  ·  %s  ·  %s"):format(
      relative_time(entry.time),
      entry.title or "task",
      core.format_command(entry.args or {})
    )
    -- 同一命令重复出现时保留最早一条，避免选择器里出现重复标签
    if not by_label[label] then
      by_label[label] = entry
      labels[#labels + 1] = label
    end
  end
  vim.ui.select(labels, { prompt = "最近任务（回车重跑）：" }, function(label)
    local entry = label and by_label[label]
    if entry then
      core.rerun(entry)
    end
  end)
end

--- 任务菜单（供主菜单之外的独立入口使用）
function M.task_menu()
  local actions = {
    { "restore", M.restore },
    { "build(Debug)", function()
      M.build("Debug")
    end },
    { "build(Release)", M.build_release },
    { "build + run", M.build_and_run },
    { "run", M.run },
    { "watch", M.watch },
    { "publish", M.publish },
    { "test", M.test },
    { "format", M.format },
    { "clean", M.clean },
    { "pack", M.pack },
  }
  local labels = {}
  for _, action in ipairs(actions) do
    labels[#labels + 1] = action[1]
  end
  vim.ui.select(labels, { prompt = "dotnet 任务：" }, function(_, index)
    if index then
      actions[index][2]()
    end
  end)
end

return M
