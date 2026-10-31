-- WPF Assistant - 模板模块
-- 提供 XAML / code-behind / ViewModel / csproj 片段等纯文本模板（不落盘）。

local M = {}

local XAML_NS = {
  'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"',
  'xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"',
}

local DESIGN_NS = {
  'xmlns:d="http://schemas.microsoft.com/expression/blend/2008"',
  'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"',
  'mc:Ignorable="d"',
}

--- 新建 XAML 时可选的文件种类
--- root     : XAML 根元素
--- base     : code-behind 基类（nil 表示不生成 code-behind）
--- dir      : config.directories 中的键
--- default  : 默认文件名（不含扩展名）
--- csharp   : 生成 code-behind 时需要的 using
M.kinds = {
  window = {
    root = "Window",
    base = "Window",
    dir = "views",
    default = "MainWindow",
    usings = { "System.Windows" },
    description = "WPF 窗口（Window）",
  },
  usercontrol = {
    root = "UserControl",
    base = "UserControl",
    dir = "controls",
    default = "MyControl",
    usings = { "System.Windows.Controls" },
    description = "用户控件（UserControl）",
  },
  page = {
    root = "Page",
    base = "Page",
    dir = "views",
    default = "MyPage",
    usings = { "System.Windows.Controls" },
    description = "页面（Page，用于 Frame/NavigationWindow）",
  },
  resource_dictionary = {
    root = "ResourceDictionary",
    base = nil,
    dir = "resources",
    default = "Styles",
    description = "资源字典（ResourceDictionary，样式/画刷/模板）",
  },
  view = {
    root = "UserControl",
    base = "UserControl",
    dir = "views",
    default = "MainView",
    usings = { "System.Windows.Controls" },
    description = "MVVM 视图（View + ViewModel 成对生成）",
  },
}

--- @return string[]
function M.kind_names()
  local names = {}
  for name in pairs(M.kinds) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- @return table|nil
function M.kind(name)
  return M.kinds[(name or ""):lower()]
end

--- XAML 文件内容
--- @param kind_name string
--- @param class string 类名（不含命名空间）
--- @param namespace string
function M.xaml(kind_name, class, namespace)
  local info = M.kind(kind_name) or M.kinds.window
  local attributes = {}
  local function add(line)
    attributes[#attributes + 1] = line
  end

  if info.root == "ResourceDictionary" then
    return table.concat({
      '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"',
      '                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">',
      "",
      "  <!-- 在此添加样式、画刷、控件模板 -->",
      "",
      "</ResourceDictionary>",
      "",
    }, "\n")
  end

  add(("x:Class=\"%s.%s\""):format(namespace, class))
  for _, line in ipairs(XAML_NS) do
    add(line)
  end
  for _, line in ipairs(DESIGN_NS) do
    add(line)
  end

  if info.root == "Window" then
    add(("Title=\"%s\" Height=\"450\" Width=\"800\""):format(class))
    add('WindowStartupLocation="CenterScreen"')
  elseif info.root == "Page" then
    add(("Title=\"%s\""):format(class))
    add('d:DesignHeight="450" d:DesignWidth="800"')
  else
    add('d:DesignHeight="450" d:DesignWidth="800"')
  end

  local lines = { ("<%s"):format(info.root) }
  for _, attribute in ipairs(attributes) do
    lines[#lines + 1] = "    " .. attribute
  end
  lines[#lines] = lines[#lines] .. ">"
  lines[#lines + 1] = "  <Grid>"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  </Grid>"
  lines[#lines + 1] = ("</%s>"):format(info.root)
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

--- code-behind 内容（ResourceDictionary 不需要）
--- @param kind_name string
--- @param class string
--- @param namespace string
--- @param opts? { view_model?: string }
function M.code_behind(kind_name, class, namespace, opts)
  opts = opts or {}
  local info = M.kind(kind_name) or M.kinds.window
  if not info.base then
    return nil
  end

  local usings = { "using System.Windows;", "using System.Windows.Controls;" }
  if opts.view_model then
    usings[#usings + 1] = "using " .. namespace .. ".ViewModels;"
  end
  table.sort(usings)

  local lines = {}
  for _, line in ipairs(usings) do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("namespace %s;"):format(namespace)
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("public partial class %s : %s"):format(class, info.base)
  lines[#lines + 1] = "{"
  lines[#lines + 1] = ("    public %s()"):format(class)
  lines[#lines + 1] = "    {"
  lines[#lines + 1] = "        InitializeComponent();"
  if opts.view_model then
    lines[#lines + 1] = ("        DataContext = new %s();"):format(opts.view_model)
  end
  lines[#lines + 1] = "    }"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

--- ViewModel 内容（INotifyPropertyChanged 骨架）
function M.view_model(class, namespace)
  return table.concat({
    "using System.Collections.Generic;",
    "using System.ComponentModel;",
    "using System.Runtime.CompilerServices;",
    "",
    ("namespace %s.ViewModels;"):format(namespace),
    "",
    ("public class %s : INotifyPropertyChanged"):format(class),
    "{",
    "    public event PropertyChangedEventHandler? PropertyChanged;",
    "",
    "    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)",
    "    {",
    "        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));",
    "    }",
    "",
    "    protected bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)",
    "    {",
    "        if (EqualityComparer<T>.Default.Equals(field, value))",
    "        {",
    "            return false;",
    "        }",
    "",
    "        field = value;",
    "        OnPropertyChanged(propertyName);",
    "        return true;",
    "    }",
    "}",
    "",
  }, "\n")
end

--- MVVM 模板下的 App.xaml（把启动窗口指向 Views/MainView.xaml）
function M.app_xaml(namespace, startup_uri)
  return table.concat({
    '<Application x:Class="' .. namespace .. '.App"',
    '             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"',
    '             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"',
    '             StartupUri="' .. (startup_uri or "Views/MainView.xaml") .. '">',
    "    <Application.Resources>",
    "        ",
    "    </Application.Resources>",
    "</Application>",
    "",
  }, "\n")
end

function M.app_xaml_cs(namespace)
  return table.concat({
    "using System.Windows;",
    "",
    ("namespace %s;"):format(namespace),
    "",
    "public partial class App : Application",
    "{",
    "}",
    "",
  }, "\n")
end

--- 非 SDK 风格工程需要在 .csproj 里显式登记文件；返回 XML 片段
--- @param kind_name string
--- @param rel_path string 相对 .csproj 的路径（使用 / 分隔）
--- @param opts? { code_behind?: string }
--- @return string
function M.csproj_entry(kind_name, rel_path, opts)
  opts = opts or {}
  local win_path = rel_path:gsub("/", "\\")
  local info = M.kind(kind_name)
  local is_xaml = rel_path:lower():match("%.xaml$") ~= nil

  if kind_name == "app" and is_xaml then
    return ('    <ApplicationDefinition Include="%s">\n'
      .. "      <Generator>MSBuild:Compile</Generator>\n"
      .. "      <SubType>Designer</SubType>\n"
      .. "    </ApplicationDefinition>"):format(win_path)
  end

  if is_xaml then
    local lines = {
      ('    <Page Include="%s">'):format(win_path),
      "      <Generator>MSBuild:Compile</Generator>",
      "      <SubType>Designer</SubType>",
    }
    if opts.code_behind then
      lines[#lines + 1] = ("      <DependentUpon>%s</DependentUpon>"):format(opts.code_behind)
    end
    lines[#lines + 1] = "    </Page>"
    return table.concat(lines, "\n")
  end

  if (info == nil) and rel_path:lower():match("%.resx$") then
    return ('    <EmbeddedResource Include="%s" />'):format(win_path)
  end

  return ('    <Compile Include="%s" />'):format(win_path)
end

return M
