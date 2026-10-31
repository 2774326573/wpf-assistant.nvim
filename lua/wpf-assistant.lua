-- WPF Assistant - 主模块
-- 对外 API：setup / 键位 / 各功能入口（构建、项目、XAML 生成、设计器、诊断、历史）。
-- 具体实现按职责拆到 config / core / system / templates / file_manager / project_manager /
-- build_manager / designer / doctor / history / ui 模块。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local ui = require("wpf-assistant.ui")

--- 初始化（在 lazy.nvim 的 config 里调用）
--- @param user_config? table
function M.setup(user_config)
  local cfg = config.setup(user_config)

  -- 把设计器路径同步到 vim.g，外部 :XamlDesigner 等命令也能用
  config.apply_designer_global()

  -- .xaml/.axaml 按 xml 高亮（其他配置可能已注册，重复注册无副作用）
  vim.filetype.add({ extension = { xaml = "xml", axaml = "xml" } })

  if cfg.enable_default_keymaps then
    M.setup_keymaps()
  end

  return cfg
end

--- @return table
function M.get_config()
  return config.get()
end

--- 键位：<leader>w* （前缀与预设可在 setup 里改）
function M.setup_keymaps()
  local prefix = config.get_value("keymaps.prefix", "<leader>w")
  local preset = config.get_value("keymaps.preset", "full")

  local map = vim.keymap.set
  local function bind(key, action, desc, modes)
    map(modes or "n", prefix .. key, action, { silent = true, desc = "WPF: " .. desc })
  end

  -- 原有的最小集合，保持习惯不变
  bind("a", M.show_menu, "Assistant 菜单")
  bind("h", M.show_help, "帮助")
  bind("b", function()
    M.build()
  end, "Debug 构建")
  bind("B", function()
    M.build("Release")
  end, "Release 构建")
  bind("r", M.run, "运行")
  bind("w", M.watch, "dotnet watch")
  bind("x", function()
    require("wpf-assistant.designer").open_interactive()
  end, "XAML 设计器")
  bind("f", M.format, "dotnet format")
  bind("c", M.clean, "clean")
  bind("p", M.publish, "发布 win-x64")
  bind("o", M.open_project_interactive, "选择项目文件")

  if preset == "minimal" then
    return
  end

  bind("N", M.new_project_interactive, "新建项目")
  bind("n", M.new_xaml_interactive, "新建 XAML 文件")
  bind("g", M.generate_code_behind, "从 XAML 生成 code-behind")
  bind("G", M.generate_view, "从 XAML 生成 ViewModel")
  bind("A", M.build_and_run, "构建并运行")
  bind("R", M.restore, "dotnet restore")
  bind("T", M.test, "dotnet test")
  bind("P", M.pack, "dotnet pack")
  bind("K", M.select_target, "选择构建目标")
  bind("C", M.select_configuration, "切换 Debug/Release")
  bind("S", M.select_startup_project, "选择启动项目")
  bind("U", M.add_project_to_solution, "把项目加入解决方案")
  bind("i", M.info, "工程信息")
  bind("H", M.show_history, "最近任务")
  bind("D", M.doctor, "环境诊断")
  bind("X", M.debug_start, "启动调试")
  bind("Y", M.debug_attach, "附加到进程")
  bind("Z", M.debug_setup, "调试状态 / 环境准备")
  bind("L", M.lsp_info, "C# LSP 状态")
  bind("F", M.generate_doc, "生成文档")
  bind("Q", M.packages_menu, "NuGet 包管理")
end

-- ==================== 构建 / 运行 ====================

function M.build(configuration)
  require("wpf-assistant.build_manager").build(configuration)
end

function M.build_and_run()
  require("wpf-assistant.build_manager").build_and_run()
end

function M.run()
  require("wpf-assistant.build_manager").run()
end

function M.watch()
  require("wpf-assistant.build_manager").watch()
end

function M.publish()
  require("wpf-assistant.build_manager").publish()
end

function M.restore()
  require("wpf-assistant.build_manager").restore()
end

function M.test()
  require("wpf-assistant.build_manager").test()
end

function M.pack()
  require("wpf-assistant.build_manager").pack()
end

function M.clean()
  require("wpf-assistant.build_manager").clean()
end

function M.format()
  require("wpf-assistant.build_manager").format()
end

function M.task_menu()
  require("wpf-assistant.build_manager").task_menu()
end

function M.show_history()
  require("wpf-assistant.build_manager").show_history()
end

function M.select_target()
  require("wpf-assistant.build_manager").select_target()
end

function M.select_configuration()
  require("wpf-assistant.build_manager").select_configuration()
end

-- ==================== 项目 ====================

--- 兼容旧接口：M.open_project() 无参数时弹出选择器
function M.open_project(path)
  local project_manager = require("wpf-assistant.project_manager")
  if path and path ~= "" then
    project_manager.open_project(path)
  else
    project_manager.open_project_interactive()
  end
end

function M.open_project_interactive()
  require("wpf-assistant.project_manager").open_project_interactive()
end

function M.new_project_interactive()
  require("wpf-assistant.project_manager").new_project_interactive()
end

--- 以脚本方式新建项目（也便于测试）
function M.new_project(name, template, opts)
  return require("wpf-assistant.project_manager").new_project(name, template, opts)
end

function M.select_startup_project()
  require("wpf-assistant.project_manager").select_startup_project()
end

function M.add_project_to_solution()
  require("wpf-assistant.project_manager").add_project_to_solution()
end

function M.info()
  require("wpf-assistant.project_manager").info()
end

-- ==================== XAML ====================

--- 新建 XAML（脚本方式）
function M.new_xaml(kind, name, opts)
  return require("wpf-assistant.file_manager").new_xaml(kind, name, opts)
end

function M.new_xaml_interactive()
  local templates = require("wpf-assistant.templates")
  local names = templates.kind_names()
  local labels = {}
  for index, name in ipairs(names) do
    labels[index] = ("%s — %s"):format(name, templates.kinds[name].description or "")
  end
  vim.ui.select(labels, { prompt = "新建 XAML 类型：" }, function(_, index)
    if not index then
      return
    end
    local kind = names[index]
    local info = templates.kinds[kind]
    ui.input("文件名/类名", info.default, function(name)
      require("wpf-assistant.file_manager").new_xaml(kind, name)
    end)
  end)
end

function M.generate_code_behind()
  require("wpf-assistant.file_manager").generate_code_behind(nil)
end

function M.generate_view()
  require("wpf-assistant.file_manager").generate_view(nil)
end

-- ==================== 设计器 / 诊断 ====================

function M.open_designer(file)
  require("wpf-assistant.designer").open(file)
end

function M.select_designer_file()
  require("wpf-assistant.designer").select()
end

function M.doctor()
  require("wpf-assistant.doctor").show()
end

-- ==================== 调试（nvim-dap + netcoredbg） ====================

function M.debug_start()
  require("wpf-assistant.debug").start()
end

function M.debug_attach()
  require("wpf-assistant.debug").attach()
end

function M.debug_status()
  require("wpf-assistant.debug").status()
end

function M.debug_setup()
  require("wpf-assistant.debug").setup_debugging()
end

-- ==================== LSP / 文档 / NuGet ====================

function M.lsp_info()
  require("wpf-assistant.lsp").info()
end

function M.lsp_restore()
  require("wpf-assistant.lsp").restore()
end

--- 生成文档：不传类型时弹出选择
function M.generate_doc(doc_type, output)
  local docs = require("wpf-assistant.docs")
  if not doc_type or doc_type == "" then
    docs.pick()
    return
  end
  docs.show(doc_type, output)
end

function M.packages_menu()
  require("wpf-assistant.packages").menu()
end

function M.list_packages()
  require("wpf-assistant.packages").report()
end

function M.add_package(package, version)
  require("wpf-assistant.packages").add(package, version)
end

function M.remove_package(package)
  require("wpf-assistant.packages").remove(package)
end

function M.update_package(package)
  require("wpf-assistant.packages").update(package)
end

-- ==================== 帮助 / 菜单 ====================

function M.show_menu()
  ui.main_menu()
end

function M.show_help()
  local prefix = config.get_value("keymaps.prefix", "<leader>w")
  local lines = {
    "# WPF Assistant 帮助",
    "",
    ("键位前缀：`%s`（可在 setup({ keymaps = { prefix = ... } }) 里改）"):format(prefix),
    "",
    "## 键位",
    "",
    ("- `%sa`  主菜单"):format(prefix),
    ("- `%sb` / `%sB`  Debug / Release 构建"):format(prefix, prefix),
    ("- `%sA`  构建并运行，`%sr` 运行，`%sw` dotnet watch"):format(prefix, prefix, prefix),
    ("- `%sR`  restore，`%sT` test，`%sP` pack，`%sf` format，`%sc` clean"):format(prefix, prefix, prefix, prefix, prefix),
    ("- `%sp`  发布 win-x64，`%sK` 选择构建目标，`%sC` 切换 Debug/Release"):format(prefix, prefix, prefix),
    ("- `%sN`  新建项目，`%sn` 新建 XAML，`%sg` 生成 code-behind，`%sG` 生成 ViewModel"):format(prefix, prefix, prefix, prefix),
    ("- `%sS`  选择启动项目，`%sU` 加入解决方案，`%si` 工程信息，`%so` 选择项目文件"):format(prefix, prefix, prefix, prefix),
    ("- `%sx`  用设计器打开当前 XAML，`%sD` 环境诊断，`%sH` 最近任务，`%sh` 本帮助"):format(prefix, prefix, prefix, prefix),
    ("- `%sX`  启动调试，`%sY` 附加到进程，`%sZ` 调试状态/环境准备"):format(prefix, prefix, prefix),
    ("- `%sL`  C# LSP 状态，`%sF` 生成文档，`%sQ` NuGet 包管理"):format(prefix, prefix, prefix),
    "",
    "## 命令",
    "",
    "| 命令 | 说明 |",
    "| --- | --- |",
    "| `:WpfAssistant` | 主菜单 |",
    "| `:WpfNewProject [name] [template]` | 新建 .NET/WPF 项目（模板：wpf_app, mvvm, classlib, console, xunit） |",
    "| `:WpfOpenProject [path]` | 打开解决方案/项目文件（无参数则选择） |",
    "| `:WpfSelectProject` | 选择启动项目 |",
    "| `:WpfAddProject` | 把 .csproj 加入解决方案 |",
    "| `:WpfInfo` | 工程信息 |",
    "| `:WpfNewXaml [kind] [name]` | 新建 XAML（window, usercontrol, page, resource_dictionary, view） |",
    "| `:WpfGenerateClass` | 为当前 XAML 生成 code-behind |",
    "| `:WpfGenerateView` | 为当前 XAML 生成 ViewModel 并挂 DataContext |",
    "| `:WpfDesigner` | 用独立设计器打开当前 XAML |",
    "| `:WpfBuild [configuration]` | dotnet build |",
    "| `:WpfBuildRun` | 构建成功后运行 |",
    "| `:WpfRun` / `:WpfWatch` | dotnet run / dotnet watch |",
    "| `:WpfPublish` | 发布 win-x64（配置见 build.publish） |",
    "| `:WpfRestore` / `:WpfTest` / `:WpfPack` | dotnet restore / test / pack |",
    "| `:WpfClean` / `:WpfFormat` | dotnet clean / format |",
    "| `:WpfTarget` / `:WpfConfiguration` | 选择构建目标 / Debug-Release |",
    "| `:WpfTasks` | 最近任务（可重跑） |",
    "| `:WpfDebug` / `:WpfDebugAttach` | 启动调试（必要时先构建）/ 附加到运行中的进程 |",
    "| `:WpfDebugStatus` / `:WpfDebugSetup` | 调试状态 / 注册适配器与配置并自查 |",
    "| `:WpfLsp` / `:WpfLspRestore` | C# 语言服务器状态 / 生成还原产物（obj/project.assets.json） |",
    "| `:WpfGenerateDoc [type] [output]` | 生成文档（project_doc, module_doc, api_doc, packages_doc） |",
    "| `:WpfListPackages` / `:WpfAddPackage [pkg] [ver]` | 依赖清单 / 添加包 |",
    "| `:WpfUpdatePackage [pkg]` / `:WpfRemovePackage [pkg]` | 升级到最新 / 移除包 |",
    "| `:WpfNuGet` | NuGet 包管理菜单 |",
    "| `:WpfDoctor` | 环境诊断 |",
    "| `:WpfHelp` | 本帮助 |",
    "",
    "## 说明",
    "",
    "- 所有构建类命令都在底部终端分栏异步执行，退出码会以通知形式返回。",
    "- 项目根目录按当前缓冲区向上查找 `.sln/.slnx/.csproj` 得到（任务终端内会沿用启动时的根目录）。",
    "- SDK 风格工程的新文件靠通配符自动纳入编译；非 SDK 风格工程才会写回 `.csproj`。",
  }
  ui.scratch("WpfAssistant://help", lines)
end

return M
