# wpf-assistant.nvim

Neovim assistant for .NET / WPF projects. Feature layout follows
[qt-assistant.nvim](https://github.com/2774326573/qt-assistant.nvim): project management,
XAML scaffolding, designer integration, build/run/publish, task history and environment
diagnostics — all without leaving the editor.

中文文档见 [README_zh.md](README_zh.md)。

## Features

- **Projects** — create .NET/WPF projects from `dotnet new` templates (`wpf_app`, `mvvm`,
  `classlib`, `console`, `xunit`), optionally with a solution and an xUnit test project; pick
  the startup project, add an existing `.csproj` to the solution, inspect project info.
- **XAML scaffolding** — Window / UserControl / Page / ResourceDictionary / MVVM View
  templates. Namespaces are derived from the project's `RootNamespace` and folder layout;
  a matching `xaml.cs` code-behind is generated (MVVM views also get a `ViewModel` wired as
  `DataContext`).
- **Designer integration** — reuses an existing `:XamlDesigner` command when your config
  provides one, otherwise launches the configured/detected designer as a detached process.
- **Build management** — restore / build (Debug & Release) / build+run / run / watch /
  publish / test / pack / clean / format, all async in a bottom terminal split with the exit
  code reported back.
- **Targets & configuration** — build target (`.sln`/`.slnx`/`.csproj`) and Debug/Release are
  remembered per project root; publish RID, self-contained flag and output dir are configurable.
- **Task history** — recent tasks per project root, re-runnable from a picker.
- **WpfDoctor** — one command reporting dotnet SDKs, XAML designer, netcoredbg,
  csharpier/xstyler, C# language servers, project state and hints for what is missing.
- **Debugging (nvim-dap + netcoredbg)** — one-key launch (the real output path is resolved with
  `msbuild -getProperty:TargetPath`, and the project is built first when needed), attach to a
  running process, plus a debug status/env self-check.
- **C# language servers** — detects OmniSharp / csharp-ls / roslyn, reports attached clients and
  the state of `obj/project.assets.json` (the .NET analogue of clangd's `compile_commands.json`).
- **Documentation** — Markdown generated from project structure and C# XML/Doxygen comments
  (project overview, modules, public API, NuGet dependencies).
- **NuGet** — dependency listing (`dotnet list package --format json`, transitive optional),
  add / update / remove packages, dependency document.
- **Legacy project support** — SDK-style projects pick up new files via globbing; classic
  `.csproj` files get explicit `ItemGroup` entries.

## Requirements

| Requirement | Needed | Notes |
| --- | --- | --- |
| Neovim | yes | 0.10+ |
| .NET SDK | yes | `dotnet` on `PATH` (verified with 10.0.401) |
| XAML designer | optional | e.g. WpfDesigner / Kaxaml; otherwise use `dotnet watch` hot reload |
| nvim-dap + netcoredbg | optional | debugging (LazyVim's `lang.dotnet` extra ships nvim-dap; install netcoredbg via mason) |
| OmniSharp / csharp-ls | optional | C# LSP; LazyVim's `lang.dotnet` extra already configures OmniSharp |
| csharpier / xstyler | optional | C# / XAML formatting; reported by `:WpfDoctor` |

## Installation

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

Or point at a local checkout so there is only one copy to maintain:

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

## Configuration

```lua
require("wpf-assistant").setup({
  designer = {
    path = nil, -- vim.g.wpf_designer_exe / vim.g.xaml_designer_exe take precedence
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
    solution_format = "sln", -- sln (most compatible) | slnx (.NET 9+ default)
  },
  directories = {
    views = "Views",
    viewmodels = "ViewModels",
    models = "Models",
    services = "Services",
    controls = "Controls",
    dialogs = "Dialogs",
    resources = "Resources",
  },
  namespace_fallback = "App",
  new_file = {
    register_in_project = true, -- only classic (non-SDK) .csproj are edited
    open_designer = false,
  },
  build = {
    target_mode = "auto", -- auto | solution | project | prompt
    publish = { runtime = "win-x64", self_contained = false, output = "build/publish" },
    terminal = { height = 15 },
  },
  history = { limit = 20 },
  debug = {
    enabled = true,
    adapter_path = nil, -- auto-detected netcoredbg
    program = nil, -- override the launch executable; ${configuration} / ${projectDir} supported
    project = nil, -- override the launched project
    args = {},
    env = {},
    stop_at_entry = false,
    just_my_code = true,
    console = "internalConsole", -- internalConsole | integratedTerminal | externalTerminal
    build_before_debug = true, -- build first when the output is missing
  },
  lsp = {
    restore_before = false,
    servers = { "omnisharp", "roslyn_ls", "csharp_ls" },
  },
  documentation = { enabled = true, output_dir = "docs", default_type = "project_doc" },
  packages = { include_transitive = false },
  enable_default_keymaps = true,
  keymaps = { prefix = "<leader>w", preset = "full" }, -- full | minimal
})
```

With `target_mode = "auto"` the build target resolves as: remembered target → solution →
startup project.

## Keymaps

Default prefix is `<leader>w`; change `keymaps.prefix` to move the whole namespace (useful to
avoid LazyVim's window group on `<leader>wd` / `<leader>wm`).

| Key | Action | | Key | Action |
| --- | --- | --- | --- | --- |
| `<leader>wa` | main menu | | `<leader>wN` | new project |
| `<leader>wb` | Debug build | | `<leader>wn` | new XAML file |
| `<leader>wB` | Release build | | `<leader>wg` | generate code-behind |
| `<leader>wA` | build and run | | `<leader>wG` | generate ViewModel |
| `<leader>wr` | run startup project | | `<leader>wS` | select startup project |
| `<leader>ww` | dotnet watch | | `<leader>wU` | add project to solution |
| `<leader>wp` | publish win-x64 | | `<leader>wi` | project info |
| `<leader>wR` | dotnet restore | | `<leader>wo` | open project file |
| `<leader>wT` | dotnet test | | `<leader>wK` | select build target |
| `<leader>wP` | dotnet pack | | `<leader>wC` | switch Debug/Release |
| `<leader>wf` | dotnet format | | `<leader>wx` | open current XAML in designer |
| `<leader>wc` | dotnet clean | | `<leader>wD` | WpfDoctor |
| `<leader>wh` | help | | `<leader>wH` | recent tasks |
| `<leader>wX` | start debugging | | `<leader>wY` | attach to process |
| `<leader>wZ` | debug status / env setup | | `<leader>wL` | C# LSP status |
| `<leader>wF` | generate documentation | | `<leader>wQ` | NuGet package management |

> Debug keys are deliberately uppercase so they do not clash with LazyVim's window group
> (`<leader>wd` delete window, `<leader>wm` zoom); breakpoints and stepping keep the default
> nvim-dap keys (`<leader>db`, `<leader>dc`, …).

`keymaps.preset = "minimal"` keeps only `a h b B r w w x f c p o`, i.e. the original set.

## Commands

`:WpfAssistant`, `:WpfNewProject [name] [template]`, `:WpfOpenProject [path]`,
`:WpfSelectProject`, `:WpfAddProject`, `:WpfInfo`, `:WpfNewXaml [kind] [name]`,
`:WpfGenerateClass`, `:WpfGenerateView`, `:WpfDesigner [file]`, `:WpfBuild [configuration]`,
`:WpfBuildRelease`, `:WpfBuildRun`, `:WpfRun`, `:WpfWatch`, `:WpfPublish`, `:WpfRestore`,
`:WpfTest`, `:WpfPack`, `:WpfClean`, `:WpfFormat`, `:WpfTarget`, `:WpfConfiguration`,
`:WpfTasks`, `:WpfDoctor`, `:WpfHelp`, `:WpfDebug`, `:WpfDebugAttach`, `:WpfDebugStatus`,
`:WpfDebugSetup`, `:WpfLsp`, `:WpfLspRestore`, `:WpfGenerateDoc [type] [output]`,
`:WpfListPackages`, `:WpfAddPackage [package] [version]`, `:WpfUpdatePackage [package]`,
`:WpfRemovePackage [package]`, `:WpfNuGet`.

## Typical workflow

```vim
:WpfNewProject DemoApp mvvm   " solution + MVVM scaffold + App.xaml -> Views/MainView.xaml
:WpfNewXaml view MainView     " MainView.xaml + .xaml.cs + MainViewModel.cs (DataContext wired)
:WpfNewXaml window SettingsWindow
:WpfBuild
:WpfRun
:WpfWatch                     " hot reload on save
:WpfPublish                   " win-x64
:WpfDebug                     " build if needed, then launch netcoredbg
:WpfDebugAttach               " attach to a running process
:WpfListPackages              " NuGet dependency report
:WpfGenerateDoc api_doc       " Markdown API docs from XML/Doxygen comments
:WpfDoctor                    " environment self-check
```

## Implementation notes

- Modules: `config`, `system`, `core`, `templates`, `file_manager`, `project_manager`,
  `build_manager`, `designer`, `debug`, `lsp`, `docs`, `packages`, `history`, `ui`, `doctor`.
- Debugging resolves the launch executable with
  `dotnet msbuild <csproj> -getProperty:TargetPath -p:Configuration=<config>`, so custom
  `OutputPath` layouts work too; an apphost `.exe` next to the `.dll` wins, otherwise the
  `.dll` is used (netcoredbg accepts both). Only the plugin's own entry in
  `dap.configurations.cs` is replaced, user entries are kept.
- **Extension matching uses predicates**: `vim.fs.find()` / `vim.fs.root()` only match exact
  base names and explicitly do not support globs such as `"*.csproj"` for string/table
  `names` (see `:help vim.fs.find`), so the plugin always passes a function matcher.
- Project root resolution: nearest `.sln`/`.slnx` upward → nearest `.csproj` → cwd. Task
  terminal buffers remember the root they were started from.
- Solution parsing supports classic `.sln` lines and `.slnx` XML.
- Traversal skips `.git`, `.vs`, `bin`, `obj`, `node_modules`, etc.

## License

MIT

## Standalone designer and XAML Hot Reload

LeXtudio integration is included. On Windows with .NET SDK 10, run `./install-lextudio-wpf.ps1` from this plugin directory. GitHub and NuGet access is required. The default tools directory is `D:/install/wpf-nvim-tools`; use `-ToolsRoot` and set `vim.g.wpf_tools_root` for another location.

Commands: `:WpfDesigner [project.csproj]`, `:WpfHotReload [project.csproj]`, `:WpfToolsStop`. Save XAML to synchronize. The designer loads project resources and filters native SDK DLLs; toolbox groups can collapse. See [integration details](docs/LeXtudio.md) for limitations and validation.
