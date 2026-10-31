-- WPF Assistant - XAML 设计器模块
-- 复用用户配置里的 :XamlDesigner 命令（若存在），否则自己用配置/探测到的可执行文件拉起独立进程。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local system = require("wpf-assistant.system")

local function is_xaml(path)
  return type(path) == "string" and (path:lower():match("%.xaml$") ~= nil or path:lower():match("%.axaml$") ~= nil)
end

--- @return string|nil
function M.path()
  return config.designer_path()
end

function M.available()
  return M.path() ~= nil or vim.fn.exists(":XamlDesigner") == 2
end

--- 设计器缺失时的提示（和 csharp.lua 里的说明保持一致）
local function notify_missing()
  vim.notify(
    "WPF Assistant: 未找到独立 XAML 设计器。\n"
      .. "可用 vim.g.wpf_designer_exe / setup({ designer = { path = ... } }) 指定路径，\n"
      .. "或把 Kaxaml 等工具加入 PATH；也可用 <leader>ww（dotnet watch）保存即热重载预览。",
    vim.log.levels.WARN
  )
end

--- 打开指定 XAML（默认当前缓冲区）
--- @param file? string
--- @return boolean
function M.open(file)
  file = file or vim.api.nvim_buf_get_name(0)
  if not is_xaml(file) then
    core.warn("当前缓冲区不是 .xaml/.axaml 文件")
    return false
  end
  if not system.is_file(file) then
    core.error(("文件不存在：%s"):format(file))
    return false
  end

  if config.get_value('designer.backend', 'lextudio') == 'lextudio' then
    require('wpf-assistant.lextudio').start('designer', nil, file)
    return true
  end

  -- 用户配置里已有 :XamlDesigner（例如 csharp.lua 中的实现，可能带自己的探测/预览逻辑）
  if vim.fn.exists(":XamlDesigner") == 2 then
    vim.cmd(("XamlDesigner %s"):format(vim.fn.fnameescape(file)))
    return true
  end

  local exe = M.path()
  if not exe then
    notify_missing()
    return false
  end
  -- The designer reads NewFileTemplate.xaml relative to its working directory.
  file = vim.fn.fnamemodify(file, ":p")
  exe = vim.fn.exepath(exe) ~= "" and vim.fn.exepath(exe) or exe
  vim.system({ exe, file }, { detach = true, cwd = vim.fn.fnamemodify(exe, ":p:h") })
  core.info(("已在独立进程中打开设计器：%s"):format(exe))
  return true
end

--- 从项目里挑一个 XAML，然后交给回调（默认打开设计器）
function M.select(callback)
  local root = core.project_root()
  local files = require("wpf-assistant.file_manager").xaml_files(root)
  if #files == 0 then
    core.error(("项目中没有找到 .xaml 或 .axaml 文件（%s）"):format(root))
    return
  end
  callback = callback or function(file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    M.open(file)
  end
  vim.ui.select(files, {
    prompt = "选择要打开的 XAML：",
    format_item = function(file)
      return system.relpath(root, file)
    end,
  }, function(file)
    if file then
      callback(file)
    end
  end)
end

--- <leader>wx 入口：当前是 XAML 直接开设计器，否则先选文件
function M.open_interactive()
  local current = vim.api.nvim_buf_get_name(0)
  if is_xaml(current) and system.is_file(current) then
    M.open(current)
    return
  end
  M.select()
end

return M
