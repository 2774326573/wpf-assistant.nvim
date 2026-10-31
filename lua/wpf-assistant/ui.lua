-- WPF Assistant - 界面模块
-- 统一的通知、选择器、输入框，以及主菜单（两级分组）与只读报告缓冲区。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local system = require("wpf-assistant.system")

function M.notify(message, level)
  vim.notify("WPF Assistant: " .. message, level or vim.log.levels.INFO)
end

function M.info(message)
  M.notify(message, vim.log.levels.INFO)
end

function M.warn(message)
  M.notify(message, vim.log.levels.WARN)
end

function M.error(message)
  M.notify(message, vim.log.levels.ERROR)
end

--- 选择器（可带项目根以显示相对路径）
--- @param items string[]
--- @param opts { prompt: string, root?: string, labels?: string[], current?: string }
function M.select(items, opts, callback)
  opts = opts or {}
  if #items == 0 then
    M.warn(opts.empty_message or "没有可选项")
    return
  end
  vim.ui.select(items, {
    prompt = opts.prompt or "请选择：",
    format_item = function(item)
      local label = item
      if opts.labels and opts.labels[item] then
        label = opts.labels[item]
      elseif opts.root then
        label = system.relpath(opts.root, item)
      end
      if opts.current and opts.current == item then
        label = label .. "  ← 当前"
      end
      return label
    end,
  }, function(item)
    if item and callback then
      callback(item)
    end
  end)
end

function M.input(prompt, default, callback)
  vim.ui.input({ prompt = prompt .. "：", default = default }, function(value)
    if value ~= nil and value ~= "" and callback then
      callback(value)
    end
  end)
end

function M.confirm(message, callback)
  vim.ui.select({ "是", "否" }, { prompt = message }, function(choice)
    if callback then
      callback(choice == "是")
    end
  end)
end

--- 只读报告缓冲区
function M.scratch(name, lines)
  core.open_split(config.get_value("build.terminal.height", 15))
  vim.cmd("enew")
  local buffer = vim.api.nvim_get_current_buf()
  pcall(vim.api.nvim_buf_set_name, buffer, name)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].buflisted = false
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].filetype = "markdown"
  return buffer
end

--- 主菜单：先选分组，再选动作
function M.main_menu()
  local wpf = require("wpf-assistant")
  local groups = {
    {
      label = "构建 / 运行",
      items = {
        { "Debug 构建", wpf.build },
        { "Release 构建", function()
          wpf.build("Release")
        end },
        { "构建并运行", wpf.build_and_run },
        { "运行启动项目", wpf.run },
        { "dotnet watch（保存即重建）", wpf.watch },
        { "发布 win-x64", wpf.publish },
        { "dotnet restore", wpf.restore },
        { "dotnet test", wpf.test },
        { "dotnet format", wpf.format },
        { "dotnet clean", wpf.clean },
      },
    },
    {
      label = "新建 / 生成",
      items = {
        { "新建 XAML 文件…", wpf.new_xaml_interactive },
        { "从当前 XAML 生成 code-behind", wpf.generate_code_behind },
        { "从当前 XAML 生成 ViewModel", wpf.generate_view },
        { "新建 .NET/WPF 项目…", wpf.new_project_interactive },
        { "把项目加入解决方案", wpf.add_project_to_solution },
      },
    },
    {
      label = "项目 / 目标",
      items = {
        { "工程信息", wpf.info },
        { "选择启动项目", wpf.select_startup_project },
        { "选择构建目标（sln/csproj）", wpf.select_target },
        { "切换 Debug/Release", wpf.select_configuration },
        { "打开项目/解决方案文件", wpf.open_project_interactive },
      },
    },
    {
      label = "调试",
      items = {
        { "启动调试（必要时先构建）", wpf.debug_start },
        { "附加到运行中的进程", wpf.debug_attach },
        { "调试状态 / 环境准备", wpf.debug_setup },
      },
    },
    {
      label = "NuGet / 文档",
      items = {
        { "依赖清单", wpf.list_packages },
        { "添加包…", function()
          wpf.add_package()
        end },
        { "升级包到最新…", function()
          wpf.update_package()
        end },
        { "移除包…", function()
          wpf.remove_package()
        end },
        { "生成工程总览文档", function()
          wpf.generate_doc("project_doc")
        end },
        { "生成模块文档", function()
          wpf.generate_doc("module_doc")
        end },
        { "生成 API 文档", function()
          wpf.generate_doc("api_doc")
        end },
        { "生成依赖文档", function()
          wpf.generate_doc("packages_doc")
        end },
        { "C# LSP 状态", wpf.lsp_info },
      },
    },
    {
      label = "设计器 / 工具",
      items = {
        { "用设计器打开当前 XAML", function()
          require("wpf-assistant.designer").open_interactive()
        end },
        { "最近任务（重跑）", wpf.show_history },
        { "环境诊断（WpfDoctor）", wpf.doctor },
        { "帮助", wpf.show_help },
      },
    },
  }

  local labels = {}
  for index, group in ipairs(groups) do
    labels[index] = group.label
  end

  vim.ui.select(labels, { prompt = "WPF Assistant：" }, function(_, index)
    if not index then
      return
    end
    local group = groups[index]
    local items = {}
    for _, item in ipairs(group.items) do
      items[#items + 1] = item[1]
    end
    vim.ui.select(items, { prompt = group.label .. "：" }, function(choice, choice_index)
      if not choice then
        return
      end
      local action = group.items[choice_index][2]
      if action then
        action()
      end
    end)
  end)
end

return M
