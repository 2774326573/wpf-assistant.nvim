# LeXtudio WPF backend for Neovim

The local `wpf-assistant.nvim` plugin now provides:

- `:WpfDesigner [project.csproj]`: build a modern .NET WPF project and open the current XAML in the LeXtudio designer with output DLLs loaded.
- `:WpfHotReload [project.csproj]`: build and run the application with the upstream startup hook. Saving XAML sends a full-file update through its named pipe.
- `:WpfToolsStop`: stop sessions started by these commands.

`<leader>wx` uses the new designer backend by default. Set `designer.backend = "legacy"` in plugin setup to restore the previous launcher. The old `:XamlDesigner` command remains unchanged.

Tools are installed under `D:/install/wpf-nvim-tools`. Override with `vim.g.wpf_tools_root`. Upstream sources are under `D:/install/vscode-wpf-source/vscode-wpf-master` and `D:/install/lextudio-designer/WpfDesigner-vscode`.

This integration does not start VS Code or Visual Studio. Current scope is modern .NET WPF, Debug configuration, one session per project. Specify the project explicitly for multi-project solutions. Framework and multi-target project selection, debugger integration, event-handler callbacks, and incremental change classification are not implemented. Rebuild/restart after C# or dependency changes. XAML resource changes and native/vendor controls require project-specific verification. Hot reload may report partial application or require a restart; it does not promise preservation of UI state.

Upstream: https://github.com/lextudio/vscode-wpf and https://github.com/lextudio/WpfDesigner (MIT). Their source/license files remain in the installation directories. The Lua adapter implements their pipe protocol rather than hosting the VS Code extension.

Validation: upstream runtime helper and designer built successfully. A .NET 10 WPF smoke application launched from headless Neovim, received saved XAML, changed its live window title to ReloadVerified, and returned {"result":"ok: window updated"} to Neovim. Stop/exit completed. Designer launch completed; visual editing and vendor/HALCON rendering remain unverified. Designer and editor can both modify XAML: reload external changes before saving to avoid overwriting them.

New machine: install Neovim 0.10+ and .NET SDK 10 with Windows Desktop support, copy the local wpf-assistant.nvim plugin as well as the nvim configuration, then run install-lextudio-wpf.ps1. The installer needs access to GitHub and NuGet. A clean-machine installation has not yet been tested.

## Project resources and visual verification

The installer includes ProjectResources.cs and the patched PageClone.cs. The designer loads App.xaml resources without starting the application, resolves project converter assemblies and project Assets pack URIs, and provides logical resource inheritance and background rendering for PageClone. Native SDK DLLs are filtered out of the explicit assembly list.

Verified against Transformer HomePage: both TP-Link images, black HALCON view areas, dark toolbar and log area render in the standalone designer. Canvas size/zoom and designer selection outlines differ from Visual Studio. Runtime data bindings, native HALCON behavior, and camera/PLC operations still require running the application. The adapter currently assumes App.xaml next to the selected csproj. Project-specific custom startup resource loading is not executed.

Installation reproduction: install-lextudio-wpf.ps1 completed from downloaded sources into the separate empty D:/install/wpf-nvim-clean-check directory, including both resource/host patches and both compiled tools. This verifies the installation workflow on the current Windows machine with its existing SDK/NuGet cache; a pristine Windows machine was not used.
