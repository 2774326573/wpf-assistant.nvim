-- WPF Assistant - 文件模块
-- 新建 XAML（Window/UserControl/Page/ResourceDictionary/View）、生成 code-behind 与 ViewModel，
-- 并在非 SDK 风格工程里把新文件登记进 .csproj。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local system = require("wpf-assistant.system")
local templates = require("wpf-assistant.templates")

--- 文件名/类名清洗
function M.class_name(name)
  name = (name or ""):gsub("%.[Xx][Aa][Mm][Ll]$", "")
  name = name:gsub("[^%w_]", "_")
  if name == "" then
    name = "Unnamed"
  end
  if name:match("^%d") then
    name = "_" .. name
  end
  return name
end

--- 从 XAML 文件内容判断种类
--- @return string|nil
function M.detect_kind(path)
  local content = table.concat(system.read_lines(path), "\n")
  local root = content:match("<%s*([%a_][%w_%.]*)[%s>]")
  if not root then
    return nil
  end
  local tag = root:lower():gsub(".*:", "")
  local map = {
    window = "window",
    usercontrol = "usercontrol",
    page = "page",
    resourcedictionary = "resource_dictionary",
  }
  return map[tag]
end

--- ViewModel 类名：AboutView -> AboutViewModel
function M.view_model_name(class)
  local base = class:gsub("View$", "")
  if base == "" then
    base = class
  end
  return base .. "ViewModel"
end

--- 文件所属的 .csproj（向上查找后取该目录下的工程文件）
--- @return string|nil
function M.project_for(path)
  local dir = vim.fs.root(path, core.extension_matcher({ "csproj" }))
  if not dir then
    return nil
  end
  local found = vim.fs.find(core.extension_matcher({ "csproj" }), { path = dir, type = "file", limit = 1 })
  return found[1] or dir
end

--- 命名空间：RootNamespace + 相对项目目录的子目录
function M.namespace_for(path, project)
  project = project or M.project_for(path) or core.startup_project(core.project_root())
  local root_namespace = core.project_namespace(project)
  if not project then
    return root_namespace
  end
  local project_dir = core.project_dir(project)
  local dir = vim.fs.dirname(path) or project_dir
  local rel = vim.fs.relpath(project_dir, dir)
  if not rel or rel == "." or rel == "" then
    return root_namespace
  end
  local segments = {}
  for segment in vim.gsplit(rel, "[/\\]") do
    if segment ~= "" and segment ~= "." then
      segments[#segments + 1] = M.class_name(segment)
    end
  end
  if #segments == 0 then
    return root_namespace
  end
  return root_namespace .. "." .. table.concat(segments, ".")
end

local function resolve_dir(project, info, opts)
  if opts.dir and opts.dir ~= "" then
    return vim.fs.normalize((vim.fn.fnamemodify(opts.dir, ":p"):gsub("[/\\]$", "")))
  end

  local project_dir = core.project_dir(project)
  local current = vim.api.nvim_buf_get_name(0)
  if current ~= "" and vim.bo.buftype == "" then
    local dir = vim.fs.dirname(current)
    local normalized = dir and vim.fs.normalize(dir) or nil
    local in_project = normalized
      and system.is_dir(normalized)
      and vim.startswith(normalized .. "/", vim.fs.normalize(project_dir) .. "/")
    if in_project then
      return normalized
    end
  end

  local convention = info.dir and config.get_value("directories." .. info.dir)
  if convention and convention ~= "" then
    local candidate = vim.fs.joinpath(project_dir, convention)
    if system.is_dir(candidate) then
      return candidate
    end
  end

  return project_dir
end

--- 在非 SDK 风格工程中登记文件
--- @param project string|nil
--- @param entries { kind: string, rel_path: string, code_behind?: string }[]
--- @return boolean
function M.register_in_project(project, entries)
  if not config.get_value("new_file.register_in_project", true) then
    return false
  end
  if not project or not system.is_file(project) then
    return false
  end
  if core.is_sdk_style(project) then
    -- SDK 风格工程隐式包含 .cs/.xaml，写进去反而会重复
    return false
  end

  local lines = system.read_lines(project)
  if #lines == 0 then
    return false
  end

  local pending = {}
  for _, entry in ipairs(entries) do
    local win_path = entry.rel_path:gsub("/", "\\")
    local already = false
    for _, line in ipairs(lines) do
      if line:find(win_path, 1, true) then
        already = true
        break
      end
    end
    if not already then
      pending[#pending + 1] = templates.csproj_entry(entry.kind, entry.rel_path, { code_behind = entry.code_behind })
    end
  end
  if #pending == 0 then
    return false
  end

  -- 收集待插入的行
  local snippet_lines = {}
  for _, snippet in ipairs(pending) do
    for line in vim.gsplit(snippet, "\n") do
      if line ~= "" then
        snippet_lines[#snippet_lines + 1] = line
      end
    end
  end

  -- 找已有的、含 Compile/Page 等条目的 ItemGroup，插到它的 </ItemGroup> 之前
  -- 注意：Lua 模式不支持 | 选择，这里逐个判断
  local function is_item_line(line)
    return line:match("<%s*Compile") ~= nil
      or line:match("<%s*Page") ~= nil
      or line:match("<%s*ApplicationDefinition") ~= nil
      or line:match("<%s*EmbeddedResource") ~= nil
  end

  local insert_at
  local in_group = false
  local has_items = false
  for index, line in ipairs(lines) do
    if line:match("<ItemGroup") then
      in_group = true
      has_items = false
    elseif in_group and line:match("</ItemGroup>") then
      if has_items then
        insert_at = index
        break
      end
      in_group = false
    elseif in_group and is_item_line(line) then
      has_items = true
    end
  end

  if insert_at then
    for offset, line in ipairs(snippet_lines) do
      table.insert(lines, insert_at + offset - 1, line)
    end
  else
    -- 没有合适的 ItemGroup：在 </Project> 之前新建一个
    local close_index
    for index = #lines, 1, -1 do
      if lines[index]:match("</Project>") then
        close_index = index
        break
      end
    end
    if not close_index then
      return false
    end
    local block = { "  <ItemGroup>" }
    vim.list_extend(block, snippet_lines)
    block[#block + 1] = "  </ItemGroup>"
    for offset, line in ipairs(block) do
      table.insert(lines, close_index + offset - 1, line)
    end
  end

  local ok, err = system.write_file(project, table.concat(lines, "\n"))
  if not ok then
    core.warn(("登记到 %s 失败：%s"):format(vim.fs.basename(project), tostring(err)))
    return false
  end
  core.info(("已把新文件登记到 %s"):format(vim.fs.basename(project)))
  return true
end

--- 新建 XAML（可按需同时生成 code-behind / ViewModel）
--- @param kind_name string
--- @param name string 文件/类名
--- @param opts? { dir?: string, open?: boolean, open_designer?: boolean, view_model?: boolean, force?: boolean }
--- @return string|nil xaml_path
function M.new_xaml(kind_name, name, opts)
  opts = opts or {}
  local info = templates.kind(kind_name)
  if not info then
    core.error(("未知的 XAML 类型：%s（可选：%s）"):format(tostring(kind_name), table.concat(templates.kind_names(), ", ")))
    return nil
  end

  local root = core.project_root()
  local class = M.class_name(name ~= "" and name or info.default)
  local project = core.startup_project(root)
  local dir = resolve_dir(project, info, opts)
  local xaml_path = vim.fs.joinpath(dir, class .. ".xaml")
  local namespace = M.namespace_for(xaml_path, project)

  if system.is_file(xaml_path) and not opts.force then
    core.warn(("文件已存在：%s"):format(system.relpath(root, xaml_path)))
    vim.cmd("edit " .. vim.fn.fnameescape(xaml_path))
    return xaml_path
  end

  local is_view = kind_name == "view" or opts.view_model
  local view_model_class = is_view and M.view_model_name(class) or nil

  local ok, err = system.write_file(xaml_path, templates.xaml(kind_name, class, namespace))
  if not ok then
    core.error(("写入 %s 失败：%s"):format(xaml_path, tostring(err)))
    return nil
  end

  local project_dir = project and core.project_dir(project)
  local entries = {
    { kind = kind_name, rel_path = project_dir and vim.fs.relpath(project_dir, xaml_path) or class .. ".xaml" },
  }

  local code_behind = templates.code_behind(kind_name, class, namespace, {
    view_model = is_view and view_model_class or nil,
  })
  local code_behind_path
  if code_behind then
    code_behind_path = xaml_path .. ".cs"
    if not system.is_file(code_behind_path) or opts.force then
      local cs_ok, cs_err = system.write_file(code_behind_path, code_behind)
      if not cs_ok then
        core.warn(("写入 %s 失败：%s"):format(code_behind_path, tostring(cs_err)))
      else
        entries[#entries + 1] = {
          kind = "code_behind",
          rel_path = project_dir and vim.fs.relpath(project_dir, code_behind_path) or (class .. ".xaml.cs"),
          code_behind = class .. ".xaml",
        }
      end
    end
  end

  if is_view and view_model_class then
    local vm_dir = vim.fs.joinpath(core.project_dir(project), config.get_value("directories.viewmodels", "ViewModels"))
    if not system.is_dir(vm_dir) then
      pcall(vim.fn.mkdir, vm_dir, "p")
    end
    local vm_path = vim.fs.joinpath(vm_dir, view_model_class .. ".cs")
    local vm_namespace = M.namespace_for(vm_path, project)
    local vm_namespace_base = (vm_namespace:gsub("%.ViewModels$", ""))
    if not system.is_file(vm_path) then
      local vm_ok, vm_err = system.write_file(vm_path, templates.view_model(view_model_class, vm_namespace_base))
      if vm_ok then
        entries[#entries + 1] = {
          kind = "class",
          rel_path = project_dir and vim.fs.relpath(project_dir, vm_path) or (view_model_class .. ".cs"),
        }
      else
        core.warn(("写入 %s 失败：%s"):format(vm_path, tostring(vm_err)))
      end
    end
  end

  M.register_in_project(project, entries)

  if opts.open ~= false then
    vim.cmd("edit " .. vim.fn.fnameescape(xaml_path))
  end
  core.info(("已创建 %s（命名空间 %s）"):format(system.relpath(root, xaml_path), namespace))

  if opts.open_designer or config.get_value("new_file.open_designer", false) then
    require("wpf-assistant.designer").open(xaml_path)
  end

  return xaml_path
end

--- 为已存在的 XAML 补一个 code-behind
--- @return boolean
function M.generate_code_behind(xaml_path, opts)
  opts = opts or {}
  xaml_path = xaml_path or vim.api.nvim_buf_get_name(0)
  if xaml_path == "" or not xaml_path:lower():match("%.xaml$") then
    core.error("请先打开一个 .xaml/.axaml 文件")
    return false
  end

  local kind_name = M.detect_kind(xaml_path)
  local info = templates.kind(kind_name or "")
  if not info or not info.base then
    core.warn("该 XAML 是资源字典，没有 code-behind")
    return false
  end

  local class = M.class_name(vim.fs.basename(xaml_path))
  local project = M.project_for(xaml_path)
  local namespace = M.namespace_for(xaml_path, project)
  local target = xaml_path .. ".cs"
  if system.is_file(target) and not opts.force then
    core.warn(("已存在：%s"):format(system.relpath(core.project_root(), target)))
    vim.cmd("edit " .. vim.fn.fnameescape(target))
    return false
  end

  local content = templates.code_behind(kind_name, class, namespace)
  local ok, err = system.write_file(target, content)
  if not ok then
    core.error(("写入 %s 失败：%s"):format(target, tostring(err)))
    return false
  end
  local project_dir = project and core.project_dir(project)
  M.register_in_project(project, {
    {
      kind = "code_behind",
      rel_path = project_dir and vim.fs.relpath(project_dir, target) or (class .. ".xaml.cs"),
      code_behind = class .. ".xaml",
    },
  })
  vim.cmd("edit " .. vim.fn.fnameescape(target))
  core.info(("已生成 %s（命名空间 %s）"):format(vim.fs.basename(target), namespace))
  return true
end

--- 为 XAML 生成/补 ViewModel（并让 code-behind 挂上 DataContext）
function M.generate_view(xaml_path)
  xaml_path = xaml_path or vim.api.nvim_buf_get_name(0)
  if xaml_path == "" or not xaml_path:lower():match("%.xaml$") then
    core.error("请先打开一个 .xaml/.axaml 文件")
    return false
  end
  local root = core.project_root()
  local project = M.project_for(xaml_path) or core.startup_project(root)
  local class = M.class_name(vim.fs.basename(xaml_path))
  local view_model_class = M.view_model_name(class)
  local vm_dir = vim.fs.joinpath(core.project_dir(project), config.get_value("directories.viewmodels", "ViewModels"))
  if not system.is_dir(vm_dir) then
    pcall(vim.fn.mkdir, vm_dir, "p")
  end
  local vm_path = vim.fs.joinpath(vm_dir, view_model_class .. ".cs")
  local namespace = (M.namespace_for(vm_path, project):gsub("%.ViewModels$", ""))

  if not system.is_file(vm_path) then
    local ok, err = system.write_file(vm_path, templates.view_model(view_model_class, namespace))
    if not ok then
      core.error(("写入 %s 失败：%s"):format(vm_path, tostring(err)))
      return false
    end
    local project_dir = project and core.project_dir(project)
    M.register_in_project(project, {
      {
        kind = "class",
        rel_path = project_dir and vim.fs.relpath(project_dir, vm_path) or (view_model_class .. ".cs"),
      },
    })
  else
    core.info(("ViewModel 已存在：%s"):format(system.relpath(root, vm_path)))
  end

  local code_behind = xaml_path .. ".cs"
  if not system.is_file(code_behind) then
    M.generate_code_behind(xaml_path)
    code_behind = xaml_path .. ".cs"
  end
  core.info(("MVVM 骨架就绪：%s + %s"):format(vim.fs.basename(xaml_path), vim.fs.basename(vm_path)))
  return true
end

--- 列出项目内 XAML 文件
function M.xaml_files(root)
  return core.find_by_extension(root or core.project_root(), { "xaml", "axaml" })
end

return M
