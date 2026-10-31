-- WPF Assistant - 插件入口
-- 命令在这里注册（模块按需 require，尽量不影响启动时间）。

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("WPF Assistant 需要 Neovim 0.10 及以上版本", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_wpf_assistant then
  return
end
vim.g.loaded_wpf_assistant = 1

local function ensure_loaded()
  if not package.loaded["wpf-assistant"] then
    local ok, module = pcall(require, "wpf-assistant")
    if not ok then
      vim.notify("WPF Assistant 加载失败：" .. tostring(module), vim.log.levels.ERROR)
      return false
    end
    return module ~= nil
  end
  return true
end

--- 注册命令：先 require 主模块（未 setup 时使用默认配置），再执行
local function command(name, fn, opts)
  vim.api.nvim_create_user_command(name, function(args)
    if not ensure_loaded() then
      return
    end
    fn(args)
  end, opts or { desc = "WPF Assistant: " .. name })
end

local kinds = { "window", "usercontrol", "page", "resource_dictionary", "view" }
local templates = { "wpf_app", "mvvm", "classlib", "console", "xunit" }

local function complete_list(items)
  return function(arg_lead)
    local matches = {}
    for _, item in ipairs(items) do
      if vim.startswith(item, arg_lead) then
        matches[#matches + 1] = item
      end
    end
    return matches
  end
end

-- ==================== 菜单 / 帮助 / 诊断 ====================

command("WpfAssistant", function()
  require("wpf-assistant").show_menu()
end, { desc = "WPF Assistant 主菜单" })

command("WpfHelp", function()
  require("wpf-assistant").show_help()
end)

command("WpfDoctor", function()
  require("wpf-assistant").doctor()
end)

command("WpfTasks", function()
  require("wpf-assistant").show_history()
end)

-- ==================== 项目 ====================

command("WpfNewProject", function(args)
  local wpf = require("wpf-assistant")
  local parts = vim.split(args.args, "%s+", { trimempty = true })
  if #parts >= 1 then
    wpf.new_project(parts[1], parts[2] or "wpf_app", { restore = false })
  else
    wpf.new_project_interactive()
  end
end, {
  nargs = "*",
  desc = "新建 .NET/WPF 项目 [name] [template]",
  complete = function(arg_lead, cmd_line)
    local argc = #vim.split(cmd_line, "%s+", { trimempty = true })
    if argc <= 2 then
      return complete_list(templates)(arg_lead)
    end
    return {}
  end,
})

command("WpfOpenProject", function(args)
  require("wpf-assistant").open_project(args.args ~= "" and vim.fn.expand(args.args) or nil)
end, { nargs = "?", complete = "file", desc = "打开解决方案/项目文件" })

command("WpfSelectProject", function()
  require("wpf-assistant").select_startup_project()
end, { desc = "选择启动项目（run/watch/publish）" })

command("WpfAddProject", function()
  require("wpf-assistant").add_project_to_solution()
end, { desc = "把 .csproj 加入解决方案" })

command("WpfInfo", function()
  require("wpf-assistant").info()
end, { desc = "工程信息" })

-- ==================== XAML ====================

command("WpfNewXaml", function(args)
  local wpf = require("wpf-assistant")
  local parts = vim.split(args.args, "%s+", { trimempty = true })
  if #parts == 0 then
    wpf.new_xaml_interactive()
  else
    wpf.new_xaml(parts[1], parts[2] or parts[1])
  end
end, {
  nargs = "*",
  desc = "新建 XAML [kind] [name]",
  complete = function(arg_lead, cmd_line)
    local argc = #vim.split(cmd_line, "%s+", { trimempty = true })
    if argc <= 2 then
      return complete_list(kinds)(arg_lead)
    end
    return {}
  end,
})

command("WpfGenerateClass", function()
  require("wpf-assistant").generate_code_behind()
end, { desc = "为当前 XAML 生成 code-behind" })

command("WpfGenerateView", function()
  require("wpf-assistant").generate_view()
end, { desc = "为当前 XAML 生成 ViewModel 并挂 DataContext" })

command("WpfDesigner", function(args)
  local designer = require("wpf-assistant.designer")
  if args.args ~= "" then
    designer.open(vim.fn.expand(args.args))
  else
    designer.open_interactive()
  end
end, { nargs = "?", complete = "file", desc = "用独立设计器打开 XAML" })

-- ==================== 构建 / 运行 ====================

command("WpfBuild", function(args)
  require("wpf-assistant").build(args.args ~= "" and args.args or nil)
end, {
  nargs = "?",
  desc = "dotnet build [configuration]",
  complete = complete_list({ "Debug", "Release" }),
})

command("WpfBuildRelease", function()
  require("wpf-assistant").build("Release")
end)

command("WpfBuildRun", function()
  require("wpf-assistant").build_and_run()
end)

command("WpfRun", function()
  require("wpf-assistant").run()
end)

command("WpfWatch", function()
  require("wpf-assistant").watch()
end)

command("WpfPublish", function()
  require("wpf-assistant").publish()
end)

command("WpfRestore", function()
  require("wpf-assistant").restore()
end)

command("WpfTest", function()
  require("wpf-assistant").test()
end)

command("WpfPack", function()
  require("wpf-assistant").pack()
end)

command("WpfClean", function()
  require("wpf-assistant").clean()
end)

command("WpfFormat", function()
  require("wpf-assistant").format()
end)

command("WpfTarget", function()
  require("wpf-assistant").select_target()
end, { desc = "选择构建目标（sln/csproj）" })

command("WpfConfiguration", function()
  require("wpf-assistant").select_configuration()
end, { desc = "切换构建配置（Debug/Release）" })

-- ==================== 调试（nvim-dap + netcoredbg） ====================

command("WpfDebug", function()
  require("wpf-assistant").debug_start()
end, { desc = "启动调试（必要时先构建）" })

command("WpfDebugAttach", function()
  require("wpf-assistant").debug_attach()
end, { desc = "附加到运行中的 .NET 进程" })

command("WpfDebugStatus", function()
  require("wpf-assistant").debug_status()
end, { desc = "显示调试状态（dap / netcoredbg / 启动程序）" })

command("WpfDebugSetup", function()
  require("wpf-assistant").debug_setup()
end, { desc = "准备调试环境（注册适配器与启动配置）" })

-- ==================== LSP / 文档 ====================

command("WpfLsp", function()
  require("wpf-assistant").lsp_info()
end, { desc = "显示 C# 语言服务器状态" })

command("WpfLspRestore", function()
  require("wpf-assistant").lsp_restore()
end, { desc = "dotnet restore（生成 obj/project.assets.json）" })

command("WpfGenerateDoc", function(args)
  local wpf = require("wpf-assistant")
  local parts = vim.split(args.args, "%s+", { trimempty = true })
  wpf.generate_doc(parts[1], parts[2])
end, {
  nargs = "*",
  desc = "生成文档 [type] [output]（project_doc/module_doc/api_doc/packages_doc）",
  complete = function(arg_lead, cmd_line)
    local argc = #vim.split(cmd_line, "%s+", { trimempty = true })
    if argc <= 2 then
      return complete_list({ "project_doc", "module_doc", "api_doc", "packages_doc" })(arg_lead)
    end
    return complete_list({ "docs/", "docs/project_doc.md", "docs/api_doc.md" })(arg_lead)
  end,
})

-- ==================== NuGet ====================

command("WpfNuGet", function()
  require("wpf-assistant").packages_menu()
end, { desc = "NuGet 包管理菜单" })

command("WpfListPackages", function()
  require("wpf-assistant").list_packages()
end, { desc = "列出 NuGet 依赖（含传递依赖开关）" })

command("WpfAddPackage", function(args)
  local parts = vim.split(args.args, "%s+", { trimempty = true })
  require("wpf-assistant").add_package(parts[1], parts[2])
end, { nargs = "*", desc = "添加 NuGet 包 [package] [version]" })

command("WpfUpdatePackage", function(args)
  local parts = vim.split(args.args, "%s+", { trimempty = true })
  require("wpf-assistant").update_package(parts[1])
end, { nargs = "?", desc = "把包升级到最新版本 [package]" })

command("WpfRemovePackage", function(args)
  local parts = vim.split(args.args, "%s+", { trimempty = true })
  require("wpf-assistant").remove_package(parts[1])
end, { nargs = "?", desc = "移除 NuGet 包 [package]" })

-- Independent LeXtudio backend, no VS Code host required.
vim.api.nvim_create_user_command('WpfDesigner', function(o)
  require('wpf-assistant.lextudio').start('designer', o.args ~= '' and o.args or nil)
end, {nargs='?', complete='file'})
vim.api.nvim_create_user_command('WpfHotReload', function(o)
  require('wpf-assistant.lextudio').start('runtime', o.args ~= '' and o.args or nil)
end, {nargs='?', complete='file'})
vim.api.nvim_create_user_command('WpfToolsStop', function() require('wpf-assistant.lextudio').stop() end, {})
