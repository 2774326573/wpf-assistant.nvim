# wpf-assistant.nvim

Neovim assistant for .NET and WPF projects.

## Features

- Debug and Release builds
- Run and `dotnet watch`
- Clean and `dotnet format`
- Publish `win-x64`
- Select `.sln`, `.slnx`, or `.csproj` files
- Open XAML files with the configured `XamlDesigner` command
- Interactive menu and direct user commands

## Installation

With lazy.nvim:

```lua
{
  "2774326573/wpf-assistant.nvim",
  lazy = false,
  config = function()
    require("wpf-assistant").setup({
      designer = {
        path = "D:/install/WpfDesigner/build-out/Demo.XamlDesigner.exe",
      },
    })
  end,
}
```

The default designer path is:

```text
D:\install\WpfDesigner\build-out\Demo.XamlDesigner.exe
```

Override it in a project `.nvim.lua` or in the plugin setup:

```lua
vim.g.wpf_designer_exe = "C:/Tools/MyXamlDesigner.exe"
```

The global variable takes precedence over the configured default. The existing
`:XamlDesigner` command and `<leader>wx` use the selected executable.

## Keymaps

| Key | Action |
| --- | --- |
| `<leader>wa` | Open the WPF Assistant menu |
| `<leader>wb` | Debug build |
| `<leader>wB` | Release build |
| `<leader>wr` | Run the current project |
| `<leader>ww` | Start `dotnet watch` |
| `<leader>wx` | Open the XAML designer |
| `<leader>wf` | Run `dotnet format` |
| `<leader>wc` | Clean |
| `<leader>wp` | Publish `win-x64` |
| `<leader>wo` | Select a project file |

The plugin expects `dotnet` on `PATH`. The XAML designer is opened through
the `:XamlDesigner` command provided by the surrounding Neovim configuration.
