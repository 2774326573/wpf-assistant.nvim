# wpf-assistant.nvim

Neovim 的 .NET / WPF 项目助手，功能布局参考 [qt-assistant.nvim](https://github.com/2774326573/qt-assistant.nvim)：
项目管理、XAML 生成、设计器集成、构建/运行/发布、任务历史与环境诊断都在编辑器里完成。

## 功能

- **项目管理**：`dotnet new` 模板新建工程（WPF / MVVM / 类库 / 控制台 / xUnit），自动建解决方案并加入项目、可选测试工程、可选 `dotnet restore`；选择启动项目、把已有 `.csproj` 加入解决方案、查看工程信息
- **XAML 生成**：Window / UserControl / Page / ResourceDictionary / MVVM View 模板，自动推导根命名空间并生成 `xaml.cs` code-behind（View 还会生成 `ViewModel` 并挂 `DataContext`）
- **设计器集成**：复用你已有的 `:XamlDesigner` 命令（如 `csharp.lua` 里的实现），没有时按配置/探测到的可执行文件以独立进程拉起
- **构建管理**：restore / build（Debug / Release）/ build+run / run / watch / publish / test / pack / clean / format，全部在底部终端分栏异步执行，退出码以通知返回
- **目标与配置**：构建目标（`.sln`/`.slnx`/`.csproj`）与 Debug/Release 可按项目记忆；`publish` 的 RID、self-contained、输出目录可配置
- **任务历史**：每个项目根记录最近任务，选择后原样重跑
- **WpfDoctor**：一键汇总 dotnet SDK、XAML 设计器、netcoredbg、csharpier/xstyler、C# 语言服务器、工程状态与缺失项建议
- **调试（nvim-dap + netcoredbg）**：一键启动调试（用 `msbuild -getProperty:TargetPath` 解析真实输出路径，未构建时先构建再启动）、附加到运行中的进程、调试状态与适配器自查
- **C# 语言服务器**：探测 OmniSharp / csharp-ls / roslyn，报告已挂载客户端与 `obj/project.assets.json`（等价于 clangd 的 `compile_commands.json`）状态
- **文档生成**：从工程结构 + C# 源码注释（`/// <summary>` / Doxygen `@brief`）生成 Markdown（工程总览 / 模块 / 公共 API / NuGet 依赖清单）
- **NuGet 管理**：依赖清单（`dotnet list package --format json`，可含传递依赖）、添加 / 升级 / 移除包、生成依赖文档
- **非 SDK 工程适配**：SDK 风格工程靠通配符自动包含新文件；老式 `.csproj` 才会把新文件写进 `ItemGroup`

## 依赖

| 依赖 | 必需 | 说明 |
| --- | --- | --- |
| Neovim | ✅ | 0.10 及以上 |
| .NET SDK | ✅ | `dotnet` 在 PATH 中（本项目在 10.0.401 上验证） |
| XAML 设计器 | 可选 | 例如 WpfDesigner / Kaxaml；缺失时用 `<leader>ww`（dotnet watch）热重载预览 |
| nvim-dap + netcoredbg | 可选 | 调试用（LazyVim 的 `lang.dotnet` extra 已含 nvim-dap，netcoredbg 可用 mason 安装） |
| OmniSharp / csharp-ls | 可选 | C# LSP；LazyVim 的 `lang.dotnet` extra 已包含 OmniSharp 配置 |
| csharpier / xstyler | 可选 | C# / XAML 格式化；`:WpfDoctor` 会报告 |

## 安装

```lua
-- lua/plugins/wpf-assistant.lua
return {
  {
    "2774326573/wpf-assistant.nvim",
    lazy = false,
    config = function()
      require("wpf-assistant").setup({
        designer = { path = "D:/install/WpfDesigner/build-out/Demo.XamlDesigner.exe" },
      })
    end,
  },
}
```

作为本地开发副本使用（单一副本，改完立刻生效，不会再和 lazy 的克隆版本不同步）：

```lua
return {
  {
    dir = vim.fn.stdpath("config") .. "/local-plugins/wpf-assistant.nvim",
    name = "wpf-assistant.nvim",
    lazy = false,
    config = function()
      require("wpf-assistant").setup({})
    end,
  },
}
```

## 配置

```lua
require("wpf-assistant").setup({
  designer = {
    -- 也可以用 vim.g.wpf_designer_exe / vim.g.xaml_designer_exe 覆盖（优先级更高）
    path = nil,
    extra_paths = {
      "D:/install/WpfDesigner/build-out/Demo.XamlDesigner.exe",
      "D:/install/WpfDesigner/XamlDesigner/bin/Release/net9.0-windows/Demo.XamlDesigner.exe",
    },
    candidates = { "kaxaml", "xamlpadx", "xamlpad", "xaml-designer" },
  },
  dotnet = {
    exe = "dotnet",
    configuration = "Debug",
    default_template = "wpf_app",   -- 交互式新建项目时的默认模板
    solution_format = "sln",        -- sln（兼容性最好）| slnx（.NET 9+ 默认）
  },
  -- 新建文件时优先使用的目录（存在才用；否则放到当前文件所在目录或工程目录）
  directories = {
    views = "Views",
    viewmodels = "ViewModels",
    models = "Models",
    services = "Services",
    controls = "Controls",
    dialogs = "Dialogs",
    resources = "Resources",
  },
  namespace_fallback = "App",       -- 无法从 .csproj 读取 RootNamespace 时的兜底
  new_file = {
    register_in_project = true,     -- 仅非 SDK 风格工程会写回 .csproj
    open_designer = false,          -- 新建 XAML 后是否立刻用设计器打开
  },
  build = {
    target_mode = "auto",           -- auto | solution | project | prompt
    publish = { runtime = "win-x64", self_contained = false, output = "build/publish" },
    terminal = { height = 15 },
  },
  history = { limit = 20 },
  -- 调试（nvim-dap + netcoredbg）
  debug = {
    enabled = true,
    adapter_path = nil,        -- 默认自动探测 netcoredbg
    program = nil,             -- 覆盖启动程序，支持 ${configuration} / ${projectDir}
    project = nil,             -- 覆盖启动项目，默认用启动项目
    args = {},
    env = {},
    stop_at_entry = false,
    just_my_code = true,
    console = "internalConsole", -- internalConsole | integratedTerminal | externalTerminal
    build_before_debug = true,   -- 未构建时先构建再启动
  },
  -- C# 语言服务器
  lsp = {
    restore_before = false,                          -- 缺 obj/project.assets.json 时是否自动 restore
    servers = { "omnisharp", "roslyn_ls", "csharp_ls" }, -- 状态报告关注的服务器
  },
  -- 文档生成
  documentation = {
    enabled = true,
    output_dir = "docs",
    default_type = "project_doc",
  },
  packages = {
    include_transitive = false, -- 依赖清单是否默认带传递依赖
  },
  enable_default_keymaps = true,
  keymaps = { prefix = "<leader>w", preset = "full" }, -- full | minimal
})
```

`target_mode = "auto"` 的解析顺序：按项目记录过的构建目标 → 解决方案 → 启动项目。

## 键位

前缀默认 `<leader>w`，可用 `keymaps.prefix` 整体挪走（避免和 LazyVim 的窗口组 `<leader>wd`/`<leader>wm` 冲突）。

| 键位 | 动作 | | 键位 | 动作 |
| --- | --- | --- | --- | --- |
| `<leader>wa` | 主菜单 | | `<leader>wN` | 新建 .NET/WPF 项目 |
| `<leader>wb` | Debug 构建 | | `<leader>wn` | 新建 XAML 文件 |
| `<leader>wB` | Release 构建 | | `<leader>wg` | 生成 code-behind |
| `<leader>wA` | 构建并运行 | | `<leader>wG` | 生成 ViewModel |
| `<leader>wr` | 运行启动项目 | | `<leader>wS` | 选择启动项目 |
| `<leader>ww` | dotnet watch | | `<leader>wU` | 把项目加入解决方案 |
| `<leader>wp` | 发布 win-x64 | | `<leader>wi` | 工程信息 |
| `<leader>wR` | dotnet restore | | `<leader>wo` | 选择项目文件 |
| `<leader>wT` | dotnet test | | `<leader>wK` | 选择构建目标 |
| `<leader>wP` | dotnet pack | | `<leader>wC` | 切换 Debug/Release |
| `<leader>wf` | dotnet format | | `<leader>wx` | 用设计器打开当前 XAML |
| `<leader>wc` | dotnet clean | | `<leader>wD` | 环境诊断（WpfDoctor） |
| `<leader>wh` | 帮助 | | `<leader>wH` | 最近任务（可重跑） |
| `<leader>wX` | 启动调试 | | `<leader>wY` | 附加到进程 |
| `<leader>wZ` | 调试状态 / 环境准备 | | `<leader>wL` | C# LSP 状态 |
| `<leader>wF` | 生成文档 | | `<leader>wQ` | NuGet 包管理 |

> 调试相关键位刻意用大写，避免和 LazyVim 的窗口组（`<leader>wd` 删窗口、`<leader>wm` 最大化）冲突；
> 断点/单步等仍用 nvim-dap 的默认键位（`<leader>db`、`<leader>dc` 等）。

`keymaps.preset = "minimal"` 时只保留 `a h b B r w x f c p o` 这一组（与旧版插件一致）。
`<leader>wh` 帮助里也有同一张表。

## 命令

| 命令 | 说明 |
| --- | --- |
| `:WpfAssistant` | 主菜单 |
| `:WpfNewProject [name] [template]` | 新建项目（模板：`wpf_app` `mvvm` `classlib` `console` `xunit`） |
| `:WpfOpenProject [path]` | 打开解决方案/项目文件（无参数则选择） |
| `:WpfSelectProject` / `:WpfAddProject` | 选择启动项目 / 把 .csproj 加入解决方案 |
| `:WpfInfo` | 工程信息（解决方案、项目、目标框架、XAML 数量） |
| `:WpfNewXaml [kind] [name]` | 新建 XAML（`window` `usercontrol` `page` `resource_dictionary` `view`） |
| `:WpfGenerateClass` / `:WpfGenerateView` | 为当前 XAML 生成 code-behind / ViewModel |
| `:WpfDesigner [file]` | 用独立设计器打开 XAML |
| `:WpfBuild [configuration]` `:WpfBuildRelease` `:WpfBuildRun` | 构建 / Release 构建 / 构建后运行 |
| `:WpfRun` `:WpfWatch` | dotnet run / dotnet watch |
| `:WpfPublish` | 发布（RID/自包含/输出目录见 `build.publish`） |
| `:WpfRestore` `:WpfTest` `:WpfPack` `:WpfClean` `:WpfFormat` | 对应的 dotnet 子命令 |
| `:WpfTarget` `:WpfConfiguration` | 选择构建目标 / Debug-Release |
| `:WpfTasks` | 最近任务（回车重跑） |
| `:WpfDebug` / `:WpfDebugAttach` | 启动调试（必要时先构建）/ 附加到运行中的进程 |
| `:WpfDebugStatus` / `:WpfDebugSetup` | 调试状态 / 注册适配器与启动配置并自查 |
| `:WpfLsp` / `:WpfLspRestore` | C# 语言服务器状态 / `dotnet restore`（生成 `obj/project.assets.json`） |
| `:WpfGenerateDoc [type] [output]` | 生成文档（`project_doc` `module_doc` `api_doc` `packages_doc`） |
| `:WpfListPackages` / `:WpfAddPackage [pkg] [ver]` | 依赖清单 / 添加包 |
| `:WpfUpdatePackage [pkg]` / `:WpfRemovePackage [pkg]` | 升级到最新 / 移除包 |
| `:WpfNuGet` | NuGet 包管理菜单 |
| `:WpfDoctor` | 环境诊断 |
| `:WpfHelp` | 帮助 |

## 典型流程

```vim
" 1. 新建 MVVM 工程（含解决方案，可选测试工程）
:WpfNewProject DemoApp mvvm

" 2. 新建视图（生成 MainView.xaml + MainView.xaml.cs + MainViewModel.cs，并挂 DataContext）
:WpfNewXaml view MainView

" 3. 新建对话框窗口
:WpfNewXaml window SettingsWindow

" 4. 构建 → 运行 → 保存即热重载
:WpfBuild
:WpfRun
:WpfWatch

" 5. 发布 win-x64
:WpfPublish

" 6. 调试：先构建并启动（自动解析真实输出路径），或附加到已运行的进程
:WpfDebug
:WpfDebugAttach

" 7. 依赖与文档
:WpfListPackages
:WpfAddPackage CommunityToolkit.Mvvm 8.4.2
:WpfGenerateDoc api_doc

" 8. 环境自查
:WpfDoctor
```

## 调试说明

- 启动程序路径优先用 `dotnet msbuild <csproj> -getProperty:TargetPath -p:Configuration=<配置>` 解析，
  因此自定义 `OutputPath`（例如 VisionControl 的 `build/bin/VisionControl/debug`）也能自动命中；
  同目录存在 apphost `.exe` 时优先用它，否则用 `.dll`（netcoredbg 两者都能启动）
- 想固定路径时配 `debug.program`（支持 `${configuration}` / `${projectDir}`），
  或直接在项目 `.nvim.lua` 里往 `dap.configurations.cs` 追加自己的条目——本插件只增删自己那一条
- `<leader>wX` 在产物不存在时会先 `<leader>wb` 构建，构建成功后再 `dap.run()`；断点请在启动前打好

## 实现说明

- 模块划分：`config`（配置）、`system`（工具链探测/执行）、`core`（项目根、目标解析、终端任务）、
  `templates`（XAML/C#/csproj 模板）、`file_manager`（新建文件与登记）、`project_manager`（工程管理）、
  `build_manager`（dotnet 任务）、`designer`（设计器）、`debug`（nvim-dap + netcoredbg）、
  `lsp`（语言服务器与还原产物）、`docs`（文档生成）、`packages`（NuGet）、
  `history`（历史与偏好）、`ui`（选择器/菜单/报告）、`doctor`（诊断）
- **扩展名匹配用函数谓词**：`vim.fs.find()` / `vim.fs.root()` 对字符串/表形式的 `names` 只做精确 basename
  匹配，`"*.csproj"` 这类通配符不会命中（见 `:help vim.fs.find`），所以插件统一用
  `function(name) return name:match("%.csproj$") end` 形式
- 项目根解析顺序：当前缓冲区向上找 `.sln/.slnx` → 最近的 `.csproj` → 当前工作目录；
  任务终端缓冲区会记住启动时的根目录，避免在终端里再按快捷键时解析错
- 解决方案解析同时支持经典 `.sln`（`Project(...) = ...` 行）与 `.slnx`（`<Project Path="..." />`）
- 遍历工程时会跳过 `.git`、`.vs`、`bin`、`obj`、`node_modules` 等目录

## 常见问题

- **提示"项目中没有找到 .xaml"**：确认 nvim 的当前文件在工程内（项目根解析依赖当前缓冲区），
  或先 `<leader>wS`/`:WpfOpenProject` 指定工程；`:WpfDoctor` 会打印解析到的项目根与 XAML 数量
- **没有设计器**：`designer.path` / `vim.g.wpf_designer_exe` 指定路径，或用 `<leader>ww` 热重载预览
- **键位被 LazyVim 窗口组占用**：`keymaps.prefix = "<leader>W"` 之类整体挪走，或用 `preset = "minimal"`
- **老工程没有自动登记新文件**：SDK 风格工程无需登记（通配符包含）；老式 `.csproj` 需要
  `new_file.register_in_project = true`（默认开）
- **调试启动后立刻退出**：看 `<leader>wZ` 里的"启动程序"是否为已构建产物；
  WPF 应用若在 `App` 构造前抛异常会静默退出，先在终端 `<leader>wr` 跑一次确认
- **OmniSharp 不解析工程**：多为未还原（缺 `obj/project.assets.json`）——`<leader>wR` 还原，
  再用 `<leader>wL` 确认状态；也可同时装 `roslyn_ls`（`dotnet tool install -g roslyn-language-server`）

## 许可证

MIT
