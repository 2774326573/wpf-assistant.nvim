local M = {}

local defaults = {
  designer = {
    path = "D:/install/WpfDesigner/build-out/Demo.XamlDesigner.exe",
  },
}

M._config = vim.deepcopy(defaults)

local function configure_designer(config)
  local custom = vim.g.wpf_designer_exe
  if type(custom) == "string" and custom ~= "" then
    vim.g.xaml_designer_exe = custom
  elseif config.designer.path and config.designer.path ~= "" then
    vim.g.xaml_designer_exe = config.designer.path
  end
end

local function project_root()
  local file = vim.api.nvim_buf_get_name(0)
  local root = vim.fs.root(file ~= "" and file or 0, { "*.sln", "*.csproj" })
  if root then
    return root
  end
  return vim.fn.getcwd()
end

local function find_file(root, patterns)
  local files = vim.fs.find(patterns, {
    path = root,
    type = "file",
    limit = 1,
  })
  return files[1]
end

local function solution_or_project(root)
  return find_file(root, { "*.sln", "*.slnx", "*.csproj" })
end

local function current_project(root)
  local file = vim.api.nvim_buf_get_name(0)
  local current = vim.fs.root(file ~= "" and file or 0, "*.csproj")
  if current then
    return find_file(current, { "*.csproj" })
  end
  return find_file(root, { "*.csproj" })
end

local function notify_error(message)
  vim.notify("WPF Assistant: " .. message, vim.log.levels.ERROR)
end

local function run_in_terminal(args, title, root)
  root = root or project_root()
  vim.cmd("botright 15split")
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buffer, "WpfAssistant://" .. title)
  vim.bo.buflisted = false
  vim.fn.jobstart(args, {
    cwd = root,
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
        vim.notify(("WPF Assistant: %s (%s)"):format(title, code == 0 and "完成" or ("退出码 " .. code)), level)
      end)
    end,
  })
end

local function require_target(kind)
  local root = project_root()
  local target = solution_or_project(root)
  if not target then
    notify_error(("当前目录没有找到 .sln、.slnx 或 .csproj（%s）"):format(root))
    return
  end
  return root, target
end

function M.build(configuration)
  local root, target = require_target("build")
  if not target then
    return
  end
  local args = { "dotnet", "build", target, "-c", configuration or "Debug" }
  run_in_terminal(args, "build-" .. (configuration or "Debug"), root)
end

function M.run()
  local root = project_root()
  local project = current_project(root)
  if not project then
    notify_error("没有找到可运行的 .csproj")
    return
  end
  run_in_terminal({ "dotnet", "run", "--project", project }, "run", root)
end

function M.watch()
  local root = project_root()
  local project = current_project(root)
  if not project then
    notify_error("没有找到可 watch 的 .csproj")
    return
  end
  run_in_terminal({ "dotnet", "watch", "--project", project }, "watch", root)
end

function M.clean()
  local root, target = require_target("clean")
  if not target then
    return
  end
  run_in_terminal({ "dotnet", "clean", target }, "clean", root)
end

function M.publish()
  local root = project_root()
  local project = current_project(root)
  if not project then
    notify_error("没有找到可发布的 .csproj")
    return
  end
  run_in_terminal({
    "dotnet",
    "publish",
    project,
    "-c",
    "Release",
    "-r",
    "win-x64",
    "--self-contained",
    "false",
  }, "publish-win-x64", root)
end

function M.format()
  local root, target = require_target("format")
  if not target then
    return
  end
  run_in_terminal({ "dotnet", "format", target }, "format", root)
end

function M.open_designer()
  local name = vim.api.nvim_buf_get_name(0)
  if name:lower():match("%.xaml$") or name:lower():match("%.axaml$") then
    vim.cmd("XamlDesigner")
    return
  end

  local root = project_root()
  local files = vim.fs.find({ "*.xaml", "*.axaml" }, { path = root, type = "file", limit = 100 })
  if #files == 0 then
    notify_error("项目中没有找到 .xaml 或 .axaml 文件")
    return
  end
  table.sort(files)
  vim.ui.select(files, {
    prompt = "选择要打开的 XAML：",
    format_item = function(file)
      return vim.fs.relpath(root, file) or file
    end,
  }, function(file)
    if file then
      vim.cmd("edit " .. vim.fn.fnameescape(file))
      vim.cmd("XamlDesigner")
    end
  end)
end

function M.open_project()
  local root = project_root()
  local files = vim.fs.find({ "*.sln", "*.slnx", "*.csproj" }, { path = root, type = "file", limit = 100 })
  if #files == 0 then
    notify_error("当前目录没有找到 .sln、.slnx 或 .csproj")
    return
  end
  table.sort(files)
  vim.ui.select(files, {
    prompt = "选择要打开的 .NET 项目文件：",
    format_item = function(file)
      return vim.fs.relpath(root, file) or file
    end,
  }, function(file)
    if file then
      vim.cmd("edit " .. vim.fn.fnameescape(file))
    end
  end)
end

function M.show_help()
  vim.notify(
    "WPF Assistant: <leader>wb 构建 | <leader>wB Release 构建 | <leader>wr 运行 | "
      .. "<leader>ww watch | <leader>wx 设计器 | <leader>wf 格式化 | "
      .. "<leader>wc 清理 | <leader>wp 发布 | <leader>wo 选择项目",
    vim.log.levels.INFO
  )
end

function M.show_menu()
  local actions = {
    { "Debug 构建", M.build },
    { "Release 构建", function() M.build("Release") end },
    { "运行当前项目", M.run },
    { "dotnet watch", M.watch },
    { "打开 XAML 设计器", M.open_designer },
    { "dotnet format", M.format },
    { "清理项目", M.clean },
    { "发布 win-x64", M.publish },
    { "选择项目文件", M.open_project },
  }
  vim.ui.select(actions, {
    prompt = "WPF Assistant：",
    format_item = function(item)
      return item[1]
    end,
  }, function(item)
    if item then
      item[2]()
    end
  end)
end

function M.get_config()
  return M._config
end

function M.setup(user_config)
  M._config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})
  configure_designer(M._config)

  local commands = {
    WpfAssistant = M.show_menu,
    WpfBuild = function() M.build() end,
    WpfBuildRelease = function() M.build("Release") end,
    WpfRun = M.run,
    WpfWatch = M.watch,
    WpfDesigner = M.open_designer,
    WpfFormat = M.format,
    WpfClean = M.clean,
    WpfPublish = M.publish,
    WpfOpenProject = M.open_project,
    WpfHelp = M.show_help,
  }
  for name, callback in pairs(commands) do
    vim.api.nvim_create_user_command(name, callback, { desc = "WPF Assistant: " .. name })
  end

  local map = vim.keymap.set
  local opts = { silent = true }
  map("n", "<leader>wa", M.show_menu, vim.tbl_extend("force", opts, { desc = "WPF Assistant" }))
  map("n", "<leader>wh", M.show_help, vim.tbl_extend("force", opts, { desc = "WPF Assistant 帮助" }))
  map("n", "<leader>wb", M.build, vim.tbl_extend("force", opts, { desc = "WPF Debug 构建" }))
  map("n", "<leader>wB", function() M.build("Release") end, vim.tbl_extend("force", opts, { desc = "WPF Release 构建" }))
  map("n", "<leader>wr", M.run, vim.tbl_extend("force", opts, { desc = "WPF 运行" }))
  map("n", "<leader>ww", M.watch, vim.tbl_extend("force", opts, { desc = "WPF dotnet watch" }))
  map("n", "<leader>wx", M.open_designer, vim.tbl_extend("force", opts, { desc = "WPF XAML 设计器" }))
  map("n", "<leader>wf", M.format, vim.tbl_extend("force", opts, { desc = "WPF dotnet format" }))
  map("n", "<leader>wc", M.clean, vim.tbl_extend("force", opts, { desc = "WPF 清理" }))
  map("n", "<leader>wp", M.publish, vim.tbl_extend("force", opts, { desc = "WPF 发布 win-x64" }))
  map("n", "<leader>wo", M.open_project, vim.tbl_extend("force", opts, { desc = "选择 .NET 项目" }))
end

return M
