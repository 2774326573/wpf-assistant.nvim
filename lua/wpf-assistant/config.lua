-- WPF Assistant - 配置模块
-- 负责默认配置、用户覆盖、点号路径读写，以及 XAML 设计器路径解析。

local M = {}

local defaults = {
  -- 独立进程的 XAML 设计器（WPF 没有官方独立设计器，这里对接第三方/自建工具）
  designer = {
    path = nil, -- 也可用 vim.g.wpf_designer_exe / vim.g.xaml_designer_exe 指定
    extra_paths = {
      "D:/install/WpfDesigner/build-out/Demo.XamlDesigner.exe",
      "D:/install/WpfDesigner/XamlDesigner/bin/Release/net9.0-windows/Demo.XamlDesigner.exe",
    },
    candidates = { "kaxaml", "xamlpadx", "xamlpad", "xaml-designer" },
  },
  dotnet = {
    exe = "dotnet",
    configuration = "Debug",
    default_template = "wpf_app",
    -- 新建解决方案时的格式：sln（经典，兼容性最好）| slnx（.NET 9+ 的 XML 格式）
    solution_format = "sln",
  },
  -- 新建文件时的默认目录（相对项目根，取自项目内实际存在的同名目录）
  directories = {
    views = "Views",
    viewmodels = "ViewModels",
    models = "Models",
    services = "Services",
    controls = "Controls",
    dialogs = "Dialogs",
    resources = "Resources",
  },
  -- 无法从 .csproj 推断根命名空间时的兜底值
  namespace_fallback = "App",
  new_file = {
    -- 非 SDK 风格工程（老式 .csproj）才需要显式登记新文件；SDK 风格工程靠通配符自动包含
    register_in_project = true,
    -- 新建 XAML 后是否立刻用设计器打开
    open_designer = false,
  },
  build = {
    -- auto: 优先记录过的偏好 → 解决方案 → 启动项目
    -- solution / project: 强制某一种；prompt: 每次询问
    target_mode = "auto",
    auto_restore = false,
    publish = {
      runtime = "win-x64",
      self_contained = false,
      output = "build/publish",
    },
    terminal = { height = 15 },
  },
  history = { limit = 20 },
  -- nvim-dap + netcoredbg 调试
  debug = {
    enabled = true,
    adapter_path = nil, -- 默认自动探测 netcoredbg
    program = nil, -- 覆盖启动程序；支持 ${configuration} / ${projectDir}
    project = nil, -- 覆盖启动项目；默认用启动项目
    args = {},
    env = {},
    stop_at_entry = false,
    just_my_code = true,
    console = "internalConsole", -- internalConsole | integratedTerminal | externalTerminal
    -- 启动调试前若未构建，先构建再启动
    build_before_debug = true,
  },
  -- C# 语言服务器
  lsp = {
    -- 缺少 obj/project.assets.json 时是否自动 restore
    restore_before = false,
    -- 关注的服务器（用于状态报告）
    servers = { "omnisharp", "roslyn_ls", "csharp_ls" },
  },
  -- 文档生成
  documentation = {
    enabled = true,
    output_dir = "docs",
    default_type = "project_doc",
  },
  -- NuGet
  packages = {
    include_transitive = false,
  },
  enable_default_keymaps = true,
  keymaps = {
    -- 键位前缀，默认沿用 <leader>w；与 LazyVim 窗口组冲突时可整体挪走
    prefix = "<leader>w",
    preset = "full", -- full | minimal
  },
}

M._config = nil

--- @param user_config table|nil
function M.setup(user_config)
  M._config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})
  M._validate(M._config)
  return M._config
end

--- @return table
function M.get()
  if not M._config then
    return M.setup({})
  end
  return M._config
end

--- 取默认配置的副本（供 :WpfDoctor 展示等只读用途）
function M.defaults()
  return vim.deepcopy(defaults)
end

--- 点号路径读取，例如 M.get_value("build.publish.runtime")
function M.get_value(key, fallback)
  local value = M.get()
  for _, part in ipairs(vim.split(key, ".", { plain = true })) do
    if type(value) ~= "table" or value[part] == nil then
      return fallback
    end
    value = value[part]
  end
  return value
end

--- 点号路径写入
function M.set_value(key, value)
  local config = M.get()
  local parts = vim.split(key, ".", { plain = true })
  local current = config
  for i = 1, #parts - 1 do
    if type(current[parts[i]]) ~= "table" then
      current[parts[i]] = {}
    end
    current = current[parts[i]]
  end
  current[parts[#parts]] = value
  return value
end

local function readable(path)
  return type(path) == "string" and path ~= "" and vim.uv.fs_stat(path) ~= nil
end

--- 解析 XAML 设计器可执行文件路径
--- 优先级：vim.g.wpf_designer_exe > vim.g.xaml_designer_exe > 配置 > 常见安装位置 > PATH
--- @return string|nil
function M.designer_path()
  local config = M.get().designer or {}

  local explicit = {
    vim.g.wpf_designer_exe,
    vim.g.xaml_designer_exe,
    config.path,
  }
  for _, path in ipairs(explicit) do
    if type(path) == "string" and path ~= "" then
      if readable(path) or vim.fn.executable(path) == 1 then
        return path
      end
    end
  end

  for _, path in ipairs(config.extra_paths or {}) do
    if readable(path) then
      return path
    end
  end

  for _, name in ipairs(config.candidates or {}) do
    local path = vim.fn.exepath(name)
    if path ~= "" then
      return path
    end
  end

  return nil
end

--- 配置写回 vim.g，使外部 :XamlDesigner 等命令也能用同一路径
function M.apply_designer_global()
  local path = M.designer_path()
  if path then
    vim.g.xaml_designer_exe = path
  end
  return path
end

function M._validate(config)
  if type(config.directories) ~= "table" then
    vim.notify("WPF Assistant: directories 配置无效，已回退默认值", vim.log.levels.WARN)
    config.directories = vim.deepcopy(defaults.directories)
  end
  local mode = config.build and config.build.target_mode
  if mode and not vim.tbl_contains({ "auto", "solution", "project", "prompt" }, mode) then
    vim.notify(
      ("WPF Assistant: build.target_mode=%s 无效，已回退 auto"):format(tostring(mode)),
      vim.log.levels.WARN
    )
    config.build.target_mode = "auto"
  end
  return true
end

return M
