-- WPF Assistant - 文档生成模块
-- 从工程结构与 C# 源码（含 XML 文档注释）生成 Markdown 文档。
-- 对应 qt-assistant 的 :QtGenerateDoc（project_doc / api_doc / module_doc / third_party_lib_doc）。

local M = {}

local config = require("wpf-assistant.config")
local core = require("wpf-assistant.core")
local system = require("wpf-assistant.system")
local ui = require("wpf-assistant.ui")

M.types = {
  project_doc = "工程总览（结构、目标、命令）",
  module_doc = "模块文档（按项目分组）",
  api_doc = "公共 API（类型/成员 + XML 注释摘要）",
  packages_doc = "NuGet 依赖清单",
}

function M.type_names()
  local names = {}
  for name in pairs(M.types) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local SKIP_DIRS = core.skip_dirs

local function now()
  return os.date("%Y-%m-%d %H:%M")
end

local function clean_summary(text)
  text = text:gsub("<[^>]+>", " ")
  -- 兼容 Doxygen 风格注释（工程里大量使用 @brief / @param / @return）
  text = text:gsub("@brief%s*", "")
  text = text:gsub("@param%s+([%w_]+)%s*", "参数 %1：")
  text = text:gsub("@return%s*", "返回：")
  text = text:gsub("@exception%s+([%w_%.]+)%s*", "异常 %1：")
  text = text:gsub("@note%s*", "说明：")
  text = text:gsub("%s+", " ")
  return vim.trim(text)
end

local TYPE_KEYWORDS = { "class", "interface", "struct", "enum", "record" }
local TYPE_MODIFIERS = {
  partial = true,
  static = true,
  abstract = true,
  sealed = true,
  file = true,
  readonly = true,
  ref = true,
  unsafe = true,
  new = true,
}

local function modifiers_only(text)
  for word in text:gmatch("%S+") do
    if not TYPE_MODIFIERS[word] then
      return false
    end
  end
  return true
end

--- 识别类型声明行（Lua 模式不支持 | 选择，这里逐个关键字匹配）
--- @return table|nil { kind, name, modifiers, bases }
local function match_type_declaration(line)
  local trimmed = vim.trim(line)
  local access = trimmed:match("^(public)%s") or trimmed:match("^(internal)%s")
  if not access then
    return nil
  end
  local body = trimmed:sub(#access + 1)
  for _, keyword in ipairs(TYPE_KEYWORDS) do
    local modifiers, rest = body:match("^%s*(.-)%s*" .. keyword .. "%s+(.+)$")
    if rest and modifiers_only(modifiers) then
      local name, tail = rest:match("^([%w_]+)%s*(.*)$")
      if name then
        tail = (tail or ""):gsub("^<[^>]*>", "") -- 去掉泛型参数
        local bases = vim.trim((tail or ""):gsub("^:%s*", "")):gsub("[%s{]+$", "")
        return { kind = keyword, name = name, modifiers = modifiers, bases = bases, access = access }
      end
    end
  end
  return nil
end

--- 解析单个 .cs 文件里的类型与成员
--- @return { namespace: string|nil, types: table[] }
function M.parse_cs(path)
  local namespace
  local types = {}
  local current
  local summary = {}
  local in_summary_block = false

  for _, line in ipairs(system.read_lines(path)) do
    -- XML 文档注释（/// <summary>…</summary>）
    local doc = line:match("^%s*///%s?(.*)$")
    if doc then
      if doc:find("<summary>", 1, true) then
        in_summary_block = true
        doc = doc:gsub("<summary>", "")
      end
      if doc:find("</summary>", 1, true) then
        in_summary_block = false
        doc = doc:gsub("</summary>", "")
      end
      if in_summary_block or not doc:match("^%s*<") then
        summary[#summary + 1] = doc
      end
    elseif line:match("^%s*$") then
      if not in_summary_block then
        summary = {}
      end
    else
      local summary_text = clean_summary(table.concat(summary, " "))

      local namespace_name = line:match("^%s*namespace%s+([%w_%.]+)")
      if namespace_name then
        namespace = namespace_name
      end

      local declaration = match_type_declaration(line)
      if declaration then
        current = {
          kind = declaration.kind,
          name = declaration.name,
          access = declaration.access,
          modifiers = declaration.modifiers,
          bases = declaration.bases,
          summary = summary_text,
          members = {},
        }
        types[#types + 1] = current
      elseif current and line:match("^%s*public%s+") then
        local signature = line:match("^%s*(public%s+[^{;=]+)")
        if signature then
          signature = vim.trim(signature)
          local member_name = signature:match("([%w_]+)%s*%(")
            or signature:match("([%w_]+)%s*{%s*get")
            or signature:match("([%w_]+)%s*[=;]")
            or signature:match("([%w_]+)%s*$")
          if member_name then
            current.members[#current.members + 1] = {
              signature = signature,
              name = member_name,
              summary = summary_text,
            }
          end
        end
      end
      summary = {}
    end
  end

  return { namespace = namespace, types = types }
end

local function count_files(root, extensions)
  return #core.find_by_extension(root, extensions)
end

local function top_level_tree(root, depth)
  local lines = {}
  local function walk(dir, prefix, level)
    if level > depth then
      return
    end
    local entries = {}
    for name, type_ in vim.fs.dir(dir) do
      if not vim.tbl_contains(SKIP_DIRS, name) and not name:match("^%.") then
        entries[#entries + 1] = { name = name, type = type_ }
      end
    end
    table.sort(entries, function(a, b)
      if a.type ~= b.type then
        return a.type == "directory"
      end
      return a.name < b.name
    end)
    for _, entry in ipairs(entries) do
      if level > 1 or entry.type == "directory" or entry.name:match("%.csproj$") or entry.name:match("%.slnx?$") then
        lines[#lines + 1] = ("%s%s%s"):format(prefix, entry.name, entry.type == "directory" and "/" or "")
      end
      if entry.type == "directory" then
        walk(vim.fs.joinpath(dir, entry.name), prefix .. "  ", level + 1)
      end
    end
  end
  walk(root, "", 1)
  return lines
end

local function project_summary(root, project)
  local project_dir = core.project_dir(project)
  return {
    path = project,
    name = vim.fs.basename(project),
    dir = project_dir,
    framework = core.project_target_framework(project) or "?",
    namespace = core.project_namespace(project),
    sdk_style = core.is_sdk_style(project),
    cs_files = count_files(project_dir, { "cs" }),
    xaml_files = count_files(project_dir, { "xaml", "axaml" }),
  }
end

-- ==================== 各类文档 ====================

local function project_doc(root)
  local dotnet = system.detect_dotnet()
  local projects = core.projects(root)
  local lines = {
    ("# %s 工程文档"):format(vim.fs.basename(root)),
    "",
    ("生成时间：%s"):format(now()),
    "",
    "## 概览",
    "",
    ("- 项目根：`%s`"):format(root),
    ("- 解决方案：`%s`"):format(core.solution(root) and core.relpath(root, core.solution(root)) or "（无）"),
    ("- 项目数：%d"):format(#projects),
    ("- XAML 文件：%d"):format(#core.find_by_extension(root, { "xaml", "axaml" })),
    ("- dotnet：%s"):format(system.dotnet_version(dotnet) or "未找到"),
    "",
    "## 项目",
    "",
    "| 项目 | 目标框架 | 根命名空间 | SDK 风格 | .cs | .xaml |",
    "| --- | --- | --- | --- | --- | --- |",
  }
  for _, project in ipairs(projects) do
    local info = project_summary(root, project)
    lines[#lines + 1] = ("| `%s` | %s | `%s` | %s | %d | %d |"):format(
      core.relpath(root, info.path),
      info.framework,
      info.namespace,
      info.sdk_style and "是" or "否",
      info.cs_files,
      info.xaml_files
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## 目录结构"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "```text"
  for _, line in ipairs(top_level_tree(root, 2)) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = "```"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## 常用命令"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| 命令 | 说明 |"
  lines[#lines + 1] = "| --- | --- |"
  lines[#lines + 1] = "| `dotnet build <sln>` | 构建解决方案 |"
  lines[#lines + 1] = "| `dotnet run --project <csproj>` | 运行启动项目 |"
  lines[#lines + 1] = "| `dotnet publish <csproj> -c Release -r win-x64 --self-contained false` | 发布 |"
  lines[#lines + 1] = "| `dotnet test <sln>` | 运行测试 |"
  lines[#lines + 1] = "| `dotnet format <sln>` | 代码格式化 |"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "> 以上命令在 Neovim 中对应 `<leader>wb` / `<leader>wr` / `<leader>wp` / `<leader>wT` / `<leader>wf`。"
  return lines
end

local function module_doc(root)
  local projects = core.projects(root)
  local lines = {
    ("# %s 模块文档"):format(vim.fs.basename(root)),
    "",
    ("生成时间：%s"):format(now()),
    "",
  }
  for _, project in ipairs(projects) do
    local info = project_summary(root, project)
    lines[#lines + 1] = ("## %s"):format(info.name)
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("- 路径：`%s`"):format(core.relpath(root, info.path))
    lines[#lines + 1] = ("- 目标框架：%s，根命名空间：`%s`"):format(info.framework, info.namespace)
    lines[#lines + 1] = ("- 源文件：%d 个 .cs，%d 个 .xaml"):format(info.cs_files, info.xaml_files)
    lines[#lines + 1] = ""

    local namespaces = {}
    for _, file in ipairs(core.find_by_extension(info.dir, { "cs" })) do
      local parsed = M.parse_cs(file)
      local namespace = parsed.namespace or "(全局)"
      namespaces[namespace] = namespaces[namespace] or {}
      for _, type in ipairs(parsed.types) do
        table.insert(namespaces[namespace], ("`%s %s`"):format(type.kind, type.name))
      end
    end
    if next(namespaces) then
      lines[#lines + 1] = "### 命名空间与类型"
      lines[#lines + 1] = ""
      for _, namespace in ipairs(vim.tbl_keys(namespaces)) do
        table.sort(namespaces[namespace])
      end
      local ordered = vim.tbl_keys(namespaces)
      table.sort(ordered)
      for _, namespace in ipairs(ordered) do
        if #namespaces[namespace] > 0 then
          lines[#lines + 1] = ("- `%s`：%s"):format(namespace, table.concat(namespaces[namespace], "、"))
        end
      end
      lines[#lines + 1] = ""
    end

    local xaml_files = core.find_by_extension(info.dir, { "xaml", "axaml" })
    if #xaml_files > 0 then
      lines[#lines + 1] = "### XAML"
      lines[#lines + 1] = ""
      for _, file in ipairs(xaml_files) do
        lines[#lines + 1] = ("- `%s`"):format(core.relpath(root, file))
      end
      lines[#lines + 1] = ""
    end
  end
  return lines
end

local function api_doc(root)
  local projects = core.projects(root)
  local lines = {
    ("# %s 公共 API"):format(vim.fs.basename(root)),
    "",
    ("生成时间：%s"):format(now()),
    "",
    "> 由源码中的 XML 文档注释（`/// <summary>`）提取，未写注释的类型/成员摘要为空。",
    "",
  }
  for _, project in ipairs(projects) do
    local info = project_summary(root, project)
    lines[#lines + 1] = ("## %s"):format(info.name)
    lines[#lines + 1] = ""
    for _, file in ipairs(core.find_by_extension(info.dir, { "cs" })) do
      local parsed = M.parse_cs(file)
      local public_types = {}
      for _, type in ipairs(parsed.types) do
        if type.access == "public" then
          public_types[#public_types + 1] = type
        end
      end
      if #public_types > 0 then
        lines[#lines + 1] = ("### `%s`"):format(core.relpath(root, file))
        lines[#lines + 1] = ""
        for _, type in ipairs(public_types) do
          local header = ("#### %s %s"):format(type.kind, type.name)
          if type.bases ~= "" then
            header = header .. (" : %s"):format(type.bases)
          end
          lines[#lines + 1] = header
          lines[#lines + 1] = ""
          if type.summary ~= "" then
            lines[#lines + 1] = type.summary
            lines[#lines + 1] = ""
          end
          if #type.members > 0 then
            lines[#lines + 1] = "| 成员 | 摘要 |"
            lines[#lines + 1] = "| --- | --- |"
            for _, member in ipairs(type.members) do
              local signature = member.signature:gsub("|", "\\|"):gsub("%s+", " ")
              local summary = member.summary ~= "" and member.summary:gsub("|", "\\|") or ""
              lines[#lines + 1] = ("| `%s` | %s |"):format(signature, summary)
            end
            lines[#lines + 1] = ""
          end
        end
      end
    end
  end
  if #lines <= 6 then
    lines[#lines + 1] = "（没有解析到 public 类型）"
  end
  return lines
end

local function packages_doc()
  local ok, packages = pcall(require, "wpf-assistant.packages")
  if not ok then
    return { "# NuGet 依赖", "", "packages 模块不可用" }
  end
  return packages.report_lines({ summary_only = true })
end

--- @return string[] lines
function M.lines(doc_type, root)
  root = root or core.project_root()
  doc_type = doc_type or config.get_value("documentation.default_type", "project_doc")
  if doc_type == "project_doc" then
    return project_doc(root)
  elseif doc_type == "module_doc" then
    return module_doc(root)
  elseif doc_type == "api_doc" then
    return api_doc(root)
  elseif doc_type == "packages_doc" then
    return packages_doc()
  end
  return { ("# 未知文档类型：%s"):format(tostring(doc_type)), "", ("可选：%s"):format(table.concat(M.type_names(), ", ")) }
end

--- 生成文档文件
--- @return string|nil path, string|nil error
function M.generate(doc_type, output)
  local root = core.project_root()
  local lines = M.lines(doc_type, root)
  local dir = config.get_value("documentation.output_dir", "docs")
  local path = output and vim.fn.fnamemodify(vim.fn.expand(output), ":p")
    or vim.fs.joinpath(root, dir, (doc_type or "project_doc") .. ".md")
  local ok, err = system.write_file(path, table.concat(lines, "\n"))
  if not ok then
    return nil, err
  end
  return path, nil
end

--- 生成并打开
function M.show(doc_type, output)
  if not config.get_value("documentation.enabled", true) then
    core.warn("文档生成已在配置中关闭（documentation.enabled = false）")
    return
  end
  local path, err = M.generate(doc_type, output)
  if not path then
    core.error(("生成文档失败：%s"):format(tostring(err)))
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  core.info(("已生成文档：%s"):format(core.relpath(core.project_root(), path)))
end

function M.pick()
  local names = M.type_names()
  local labels = {}
  for index, name in ipairs(names) do
    labels[index] = ("%s — %s"):format(name, M.types[name])
  end
  vim.ui.select(labels, { prompt = "生成哪种文档：" }, function(_, index)
    if index then
      M.show(names[index])
    end
  end)
end

return M
