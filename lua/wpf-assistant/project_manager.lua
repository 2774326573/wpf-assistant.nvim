-- WPF Assistant - 项目管理模块
-- 新建/打开 .NET(WPF) 项目与解决方案、选择启动项目、把项目加入解决方案、查看工程信息。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local file_manager = require("wpf-assistant.file_manager")
local history = require("wpf-assistant.history")
local system = require("wpf-assistant.system")
local templates = require("wpf-assistant.templates")

--- 可用模板：dotnet new 的模板名 + 展示名
M.templates = {
  wpf_app = { dotnet = "wpf", label = "WPF 应用（dotnet new wpf）" },
  mvvm = { dotnet = "wpf", label = "WPF + MVVM 骨架（Views/ViewModels）", mvvm = true },
  classlib = { dotnet = "classlib", label = "类库（dotnet new classlib）" },
  console = { dotnet = "console", label = "控制台应用（dotnet new console）" },
  xunit = { dotnet = "xunit", label = "xUnit 测试项目（dotnet new xunit）" },
}

function M.template_names()
  local names = {}
  for name in pairs(M.templates) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function require_dotnet()
  local dotnet = system.detect_dotnet()
  if not dotnet then
    core.error("未找到 dotnet CLI，请先安装 .NET SDK 并确保它在 PATH 中")
    return nil
  end
  return dotnet
end

--- 校验项目名（同时可作为程序集名/命名空间）
function M.valid_name(name)
  if type(name) ~= "string" or name == "" then
    return false, "项目名不能为空"
  end
  if not name:match("^[%a_][%w_%.]*$") then
    return false, "项目名只能包含字母、数字、下划线，且不能以数字开头"
  end
  return true
end

local function run_step(args, cwd, label, quiet)
  local result = system.run_sync(args, { cwd = cwd })
  if not result.ok then
    if not quiet then
      local detail = vim.trim(result.stderr ~= "" and result.stderr or result.stdout)
      local tail = detail:sub(-400)
      core.error(("%s 失败：%s"):format(label, tail ~= "" and tail or ("退出码 " .. result.code)))
    end
    return false, result
  end
  return true, result
end

--- dotnet new sln 在 .NET 9+ 默认生成 .slnx，这里统一按实际文件探测
local function detect_solution(dir, name)
  for _, candidate in ipairs({
    vim.fs.joinpath(dir, name .. ".sln"),
    vim.fs.joinpath(dir, name .. ".slnx"),
  }) do
    if system.is_file(candidate) then
      return candidate
    end
  end
  local found = vim.fs.find(core.extension_matcher({ "sln", "slnx" }), { path = dir, type = "file", limit = 1 })
  return found[1]
end

local function scaffold_mvvm(project_dir, name)
  local views_dir = vim.fs.joinpath(project_dir, config.get_value("directories.views", "Views"))
  local vm_dir = vim.fs.joinpath(project_dir, config.get_value("directories.viewmodels", "ViewModels"))
  pcall(vim.fn.mkdir, views_dir, "p")
  pcall(vim.fn.mkdir, vm_dir, "p")

  local view_xaml = vim.fs.joinpath(views_dir, "MainView.xaml")
  local view_cs = view_xaml .. ".cs"
  local vm_cs = vim.fs.joinpath(vm_dir, "MainViewModel.cs")

  system.write_file(view_xaml, templates.xaml("view", "MainView", name .. ".Views"))
  system.write_file(
    view_cs,
    templates.code_behind("view", "MainView", name .. ".Views", { view_model = "MainViewModel" })
  )
  system.write_file(vm_cs, templates.view_model("MainViewModel", name))

  -- 模板自带的 MainWindow 换成 Views/MainView.xaml
  for _, leftover in ipairs({ "MainWindow.xaml", "MainWindow.xaml.cs" }) do
    local path = vim.fs.joinpath(project_dir, leftover)
    if system.is_file(path) then
      pcall(vim.fn.delete, path)
    end
  end
  local app_xaml = vim.fs.joinpath(project_dir, "App.xaml")
  if system.is_file(app_xaml) then
    local lines = system.read_lines(app_xaml)
    for index, line in ipairs(lines) do
      if line:find("StartupUri", 1, true) then
        lines[index] = line:gsub('StartupUri="[^"]*"', 'StartupUri="Views/MainView.xaml"')
      end
    end
    system.write_file(app_xaml, table.concat(lines, "\n"))
  end
  return { view_xaml, view_cs, vm_cs }
end

--- 新建项目（同步执行 dotnet new，便于随后继续脚手架）
--- @param name string 项目名
--- @param template_name string M.templates 的键
--- @param opts? table 可选：dir / layout("flat"|"src") / solution / tests / restore / open
--- @return string|nil 主项目 .csproj 路径
function M.new_project(name, template_name, opts)
  opts = opts or {}
  template_name = template_name or config.get_value("dotnet.default_template", "wpf_app")
  local template = M.templates[template_name]
  if not template then
    core.error(("未知模板：%s（可选：%s）"):format(tostring(template_name), table.concat(M.template_names(), ", ")))
    return nil
  end
  local valid, message = M.valid_name(name)
  if not valid then
    core.error(message)
    return nil
  end
  local dotnet = require_dotnet()
  if not dotnet then
    return nil
  end

  local parent = vim.fs.normalize((vim.fn.fnamemodify(opts.dir or vim.fn.getcwd(), ":p"):gsub("[/\\]$", "")))
  local root = vim.fs.joinpath(parent, name)
  local layout = opts.layout or "src"
  local project_dir = layout == "src" and vim.fs.joinpath(root, "src", name) or root

  if system.is_dir(root) and vim.fn.glob(vim.fs.joinpath(root, "**/*.csproj")) ~= "" then
    core.warn(("目录已存在同名工程：%s"):format(root))
    return nil
  end
  pcall(vim.fn.mkdir, project_dir, "p")

  local new_args = { dotnet, "new", template.dotnet, "-n", name, "-o", project_dir, "--no-restore" }
  local ok = run_step(new_args, root, ("dotnet new %s"):format(template.dotnet))
  if not ok then
    return nil
  end

  local project = vim.fs.joinpath(project_dir, name .. ".csproj")
  if not system.is_file(project) then
    core.error(("未找到生成的工程文件：%s"):format(project))
    return nil
  end

  local extras = {}
  if template.mvvm then
    extras = scaffold_mvvm(project_dir, name)
  end

  local sln
  if opts.solution ~= false then
    local format = config.get_value("dotnet.solution_format", "sln")
    -- 新版 SDK 支持 --format；老版本不认识该参数，失败后按默认格式重试
    local sln_ok = run_step(
      { dotnet, "new", "sln", "-n", name, "-o", root, "--format", format },
      root,
      "dotnet new sln",
      true
    )
    if not sln_ok then
      sln_ok = run_step({ dotnet, "new", "sln", "-n", name, "-o", root }, root, "dotnet new sln")
    end
    if sln_ok then
      sln = detect_solution(root, name)
      if sln then
        run_step({ dotnet, "sln", sln, "add", project }, root, "dotnet sln add")
      else
        core.warn("解决方案文件未找到，已跳过 dotnet sln add")
      end
    else
      sln = nil
    end
  end

  if opts.tests then
    local tests_dir = vim.fs.joinpath(root, "tests", name .. ".Tests")
    local tests_ok = run_step(
      { dotnet, "new", "xunit", "-n", name .. ".Tests", "-o", tests_dir, "--no-restore" },
      root,
      "dotnet new xunit"
    )
    if tests_ok then
      local test_project = vim.fs.joinpath(tests_dir, name .. ".Tests.csproj")
      run_step({ dotnet, "add", test_project, "reference", project }, root, "dotnet add reference")
      if sln then
        run_step({ dotnet, "sln", sln, "add", test_project }, root, "dotnet sln add")
      end
    end
  end

  if opts.restore ~= false then
    core.info("正在还原依赖（dotnet restore）…")
    run_step({ dotnet, "restore", sln or project }, root, "dotnet restore")
  end

  history.set_pref(root, "startup_project", project)
  if sln then
    history.set_pref(root, "build_target", sln)
  end

  core.info(("项目已创建：%s%s"):format(root, sln and ("（解决方案 " .. vim.fs.basename(sln) .. "）") or ""))
  if #extras > 0 then
    core.info("MVVM 骨架：Views/MainView.xaml + ViewModels/MainViewModel.cs，App.xaml 已指向 Views/MainView.xaml")
  end

  if opts.open ~= false then
    vim.cmd("edit " .. vim.fn.fnameescape(sln or project))
  end
  return project
end

--- 交互式新建项目
function M.new_project_interactive()
  local names = M.template_names()
  local labels = {}
  for index, template_name in ipairs(names) do
    labels[index] = ("%s — %s"):format(template_name, M.templates[template_name].label)
  end
  vim.ui.select(labels, { prompt = "选择项目模板：" }, function(_, index)
    if not index then
      return
    end
    local template_name = names[index]
    vim.ui.input({ prompt = "项目名：", default = "MyWpfApp" }, function(name)
      if not name or name == "" then
        return
      end
      vim.ui.input({
        prompt = "父目录：",
        default = vim.fn.getcwd(),
        completion = "dir",
      }, function(dir)
        if not dir or dir == "" then
          return
        end
        vim.ui.select({ "是（推荐）", "否" }, { prompt = "创建解决方案 .sln 并把项目加入？" }, function(choice)
          vim.ui.select({ "是", "否" }, { prompt = "同时创建 xUnit 测试项目？" }, function(with_tests)
            M.new_project(name, template_name, {
              dir = dir,
              solution = choice == "是（推荐）",
              tests = with_tests == "是",
            })
          end)
        end)
      end)
    end)
  end)
end

--- 打开项目/解决方案
--- @param path? string 目录或文件
function M.open_project(path)
  path = path and vim.fn.expand(path) or nil
  if not path or path == "" then
    path = core.project_root()
  end
  if system.is_dir(path) then
    local sln = core.solution(path)
    local target = sln or core.startup_project(path) or core.first_by_extension(path, { "csproj" })
    if not target then
      core.error(("目录里没有 .sln/.csproj：%s"):format(path))
      return
    end
    path = target
  end
  if not system.is_file(path) then
    core.error(("文件不存在：%s"):format(path))
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

function M.open_project_interactive()
  local root = core.project_root()
  local files = core.find_by_extension(root, { "sln", "slnx", "csproj" }, { limit = 100 })
  if #files == 0 then
    core.error(("当前项目里没有 .sln/.slnx/.csproj（%s）"):format(root))
    return
  end
  vim.ui.select(files, {
    prompt = "选择要打开的 .NET 项目文件：",
    format_item = function(file)
      return system.relpath(root, file)
    end,
  }, function(file)
    if file then
      vim.cmd("edit " .. vim.fn.fnameescape(file))
    end
  end)
end

--- 选择启动项目（run/watch/publish 用），按项目根记忆
function M.select_startup_project()
  local root = core.project_root()
  local projects = core.projects(root)
  if #projects == 0 then
    core.error(("没有找到 .csproj（%s）"):format(root))
    return
  end
  local current = core.startup_project(root)
  vim.ui.select(projects, {
    prompt = "选择启动项目（run / watch / publish 使用）：",
    format_item = function(project)
      local label = system.relpath(root, project)
      if project == current then
        label = label .. "  ← 当前"
      end
      local framework = core.project_target_framework(project)
      if framework then
        label = label .. ("  [%s]"):format(framework)
      end
      return label
    end,
  }, function(project)
    if project then
      history.set_pref(root, "startup_project", project)
      core.info(("启动项目已设为：%s"):format(system.relpath(root, project)))
    end
  end)
end

--- 把一个未登记的 .csproj 加入解决方案
function M.add_project_to_solution()
  local root = core.project_root()
  local sln = core.solution(root)
  if not sln then
    core.error(("没有找到解决方案文件（%s）"):format(root))
    return
  end
  local registered = {}
  for _, project in ipairs(core.solution_projects(sln)) do
    registered[vim.fs.normalize(project):lower()] = true
  end
  local candidates = {}
  for _, project in ipairs(core.projects(root)) do
    if not registered[vim.fs.normalize(project):lower()] then
      candidates[#candidates + 1] = project
    end
  end
  if #candidates == 0 then
    core.info("解决方案已包含所有 .csproj")
    return
  end
  vim.ui.select(candidates, {
    prompt = "选择要加入解决方案的项目：",
    format_item = function(project)
      return system.relpath(root, project)
    end,
  }, function(project)
    if not project then
      return
    end
    local dotnet = system.detect_dotnet()
    if not dotnet then
      core.error("未找到 dotnet CLI")
      return
    end
    core.run_in_terminal({ dotnet, "sln", sln, "add", project }, "sln-add", root, { kind = "project" })
  end)
end

--- 工程信息（写入只读 scratch 缓冲区）
function M.info()
  local root = core.project_root()
  local sln = core.solution(root)
  local projects = core.projects(root)
  local target, kind = core.build_target(root)
  local startup = core.startup_project(root)
  local xaml_files = require("wpf-assistant.file_manager").xaml_files(root)

  local lines = {
    "# WPF Assistant - 工程信息",
    "",
    ("- 项目根目录：`%s`"):format(root),
    ("- 解决方案：`%s`"):format(sln and system.relpath(root, sln) or "（无）"),
    ("- 启动项目：`%s`"):format(startup and system.relpath(root, startup) or "（未确定，用 <leader>wS 选择）"),
    ("- 构建目标：`%s`（%s）"):format(
      target and system.relpath(root, target) or "（无）",
      kind or "-"
    ),
    ("- 构建配置：`%s`"):format(
      history.get_pref(root, "configuration") or config.get_value("dotnet.configuration", "Debug")
    ),
    ("- XAML 文件：%d 个"):format(#xaml_files),
    "",
    "## 项目列表",
    "",
  }
  if #projects == 0 then
    lines[#lines + 1] = "（没有找到 .csproj）"
  else
    for _, project in ipairs(projects) do
      lines[#lines + 1] = ("- `%s`  [%s]%s"):format(
        system.relpath(root, project),
        core.project_target_framework(project) or "?",
        core.is_sdk_style(project) and "" or "  （非 SDK 风格）"
      )
    end
  end

  if sln then
    local registered = core.solution_projects(sln)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## 解决方案内项目"
    lines[#lines + 1] = ""
    if #registered == 0 then
      lines[#lines + 1] = "（解析不到，可能是 .slnx 或新格式）"
    else
      for _, project in ipairs(registered) do
        lines[#lines + 1] = ("- `%s`"):format(system.relpath(root, project))
      end
    end
  end

  require("wpf-assistant.ui").scratch("WpfAssistant://info", lines)
end

return M
