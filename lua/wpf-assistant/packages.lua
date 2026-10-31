-- WPF Assistant - NuGet 包管理模块
-- 列出/添加/移除/升级包（dotnet list|add|remove package），并生成依赖清单文档。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local system = require("wpf-assistant.system")
local ui = require("wpf-assistant.ui")

--- 当前操作对象：优先启动项目，其次构建目标
local function target_project()
  local root = core.project_root()
  return core.startup_project(root), root
end

--- 解析 `dotnet list package --format json` 的输出
--- @return table|nil data, string|nil error
function M.parse_json(stdout)
  -- 输出可能带 MSBuild/还原日志，截取第一段 JSON
  local json = (stdout or ""):match("({.*})")
  if not json then
    return nil, "无法解析 dotnet list 输出（未找到 JSON）"
  end
  local ok, decoded = pcall(vim.json.decode, json)
  if not ok or type(decoded) ~= "table" then
    return nil, "无法解析 dotnet list 输出（JSON 解析失败）"
  end
  return decoded, nil
end

--- 解析 `dotnet list package --format json`
--- @return table|nil data, string|nil error
function M.data(opts)
  opts = opts or {}
  local dotnet = system.detect_dotnet()
  if not dotnet then
    return nil, "未找到 dotnet CLI"
  end
  local root = core.project_root()
  local target = opts.target or core.build_target(root)
  if not target then
    return nil, ("没有找到 .sln/.csproj（%s）"):format(root)
  end

  local args = { dotnet, "list", target, "package", "--format", "json" }
  if opts.include_transitive or config.get_value("packages.include_transitive", false) then
    args[#args + 1] = "--include-transitive"
  end

  local result = system.run_sync(args, { cwd = root })
  if not result.ok then
    local detail = vim.trim(result.stderr ~= "" and result.stderr or result.stdout)
    return nil, (detail ~= "" and detail:sub(-300)) or ("退出码 " .. result.code)
  end
  return M.parse_json(result.stdout)
end

--- 直接依赖（用于选择器）
--- @return { project: string, package: string, version: string }[]
function M.direct_packages()
  local data = M.data()
  local packages = {}
  if not data then
    return packages
  end
  for _, project in ipairs(data.projects or {}) do
    for _, framework in ipairs(project.frameworks or {}) do
      for _, package in ipairs(framework.topLevelPackages or {}) do
        packages[#packages + 1] = {
          project = project.path,
          package = package.id,
          version = package.resolvedVersion or package.requestedVersion or "?",
        }
      end
    end
  end
  return packages
end

--- Markdown 依赖清单（供报告与文档生成复用）
--- @return string[]
function M.report_lines(opts)
  opts = opts or {}
  local data, err = M.data(opts)
  if not data then
    return {
      "# NuGet 依赖",
      "",
      ("- 获取依赖失败：%s"):format(tostring(err)),
      "",
      "- 若工程尚未还原，先运行 `:WpfRestore`（<leader>wR）",
    }
  end

  local lines = { "# NuGet 依赖", "" }
  for _, project in ipairs(data.projects or {}) do
    lines[#lines + 1] = ("## %s"):format(vim.fs.basename(project.path))
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("路径：`%s`"):format(core.relpath(core.project_root(), project.path))
    lines[#lines + 1] = ""
    for _, framework in ipairs(project.frameworks or {}) do
      local direct = framework.topLevelPackages or {}
      local transitive = framework.transitivePackages or {}
      lines[#lines + 1] = ("### %s（直接 %d，传递 %d）"):format(framework.framework, #direct, #transitive)
      lines[#lines + 1] = ""
      if #direct > 0 then
        lines[#lines + 1] = "| 直接依赖 | 请求版本 | 解析版本 |"
        lines[#lines + 1] = "| --- | --- | --- |"
        for _, package in ipairs(direct) do
          lines[#lines + 1] = ("| `%s` | %s | %s |"):format(
            package.id,
            package.requestedVersion or "-",
            package.resolvedVersion or "-"
          )
        end
        lines[#lines + 1] = ""
      end
      if #transitive > 0 and not opts.summary_only then
        lines[#lines + 1] = "<details><summary>传递依赖</summary>"
        lines[#lines + 1] = ""
        for _, package in ipairs(transitive) do
          lines[#lines + 1] = ("- `%s` %s"):format(package.id, package.resolvedVersion or "-")
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "</details>"
        lines[#lines + 1] = ""
      end
    end
  end
  return lines
end

function M.report(opts)
  ui.scratch("WpfAssistant://packages", M.report_lines(opts))
end

--- 加入包（异步在终端执行）
function M.add(package, version, project)
  local root = core.project_root()
  local dotnet = system.detect_dotnet()
  if not dotnet then
    core.error("未找到 dotnet CLI")
    return
  end
  project = project or target_project()
  if not project then
    core.error(("没有找到 .csproj（%s）"):format(root))
    return
  end
  if not package or package == "" then
    ui.input("NuGet 包名", "", function(input)
      M.add(input, version, project)
    end)
    return
  end
  local args = { dotnet, "add", project, "package", package }
  if version and version ~= "" then
    args[#args + 1] = "--version"
    args[#args + 1] = version
  end
  core.run_in_terminal(args, "add-package", root, { kind = "package", target = project })
end

--- 移除包（按直接依赖列表选择）
function M.remove(package)
  local root = core.project_root()
  local dotnet = system.detect_dotnet()
  if not dotnet then
    core.error("未找到 dotnet CLI")
    return
  end

  local function do_remove(chosen)
    local args = { dotnet, "remove", chosen.project, "package", chosen.package }
    core.run_in_terminal(args, "remove-package", root, { kind = "package", target = chosen.project })
  end

  if package and package ~= "" then
    local project = target_project()
    if not project then
      core.error("没有找到 .csproj")
      return
    end
    do_remove({ project = project, package = package })
    return
  end

  local packages = M.direct_packages()
  if #packages == 0 then
    core.info("没有可移除的直接依赖")
    return
  end
  vim.ui.select(packages, {
    prompt = "移除哪个 NuGet 包：",
    format_item = function(item)
      return ("%s  %s  (%s)"):format(vim.fs.basename(item.project), item.package, item.version)
    end,
  }, function(chosen)
    if chosen then
      do_remove(chosen)
    end
  end)
end

--- 升级包到最新（dotnet add package 已存在的包即升级）
function M.update(package)
  local packages = M.direct_packages()
  if package and package ~= "" then
    local project = target_project()
    if not project then
      core.error("没有找到 .csproj")
      return
    end
    M.add(package, nil, project)
    return
  end
  if #packages == 0 then
    core.info("没有可升级的直接依赖")
    return
  end
  vim.ui.select(packages, {
    prompt = "升级哪个包到最新版本（dotnet add package）：",
    format_item = function(item)
      return ("%s  %s  (当前 %s)"):format(vim.fs.basename(item.project), item.package, item.version)
    end,
  }, function(chosen)
    if chosen then
      M.add(chosen.package, nil, chosen.project)
    end
  end)
end

--- 包管理菜单
function M.menu()
  local actions = {
    { "查看依赖清单", function()
      M.report()
    end },
    { "添加包（dotnet add package）", function()
      M.add()
    end },
    { "升级包到最新", M.update },
    { "移除包（dotnet remove package）", function()
      M.remove()
    end },
    { "生成依赖文档（docs/packages.md）", function()
      require("wpf-assistant.docs").show("packages_doc")
    end },
  }
  local labels = {}
  for _, action in ipairs(actions) do
    labels[#labels + 1] = action[1]
  end
  vim.ui.select(labels, { prompt = "NuGet 包管理：" }, function(_, index)
    if index then
      actions[index][2]()
    end
  end)
end

return M
