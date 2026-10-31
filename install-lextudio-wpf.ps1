param([string]$ToolsRoot = 'D:/install/wpf-nvim-tools')
$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path $ToolsRoot 'sources'
New-Item -ItemType Directory -Force $sourceRoot | Out-Null
function Get-Source($Repo, $Branch, $Name) {
  $zip = Join-Path $sourceRoot "$Name.zip"
  $destination = Join-Path $sourceRoot $Name
  Invoke-WebRequest "https://codeload.github.com/lextudio/$Repo/zip/refs/heads/$Branch" -OutFile $zip
  Expand-Archive $zip $destination -Force
  return Join-Path $destination "$Repo-$Branch"
}
$extension = Get-Source 'vscode-wpf' 'master' 'extension'
$designer = Get-Source 'WpfDesigner' 'vscode' 'designer'
dotnet build "$extension/src/WpfHotReload.Runtime/WpfHotReload.Runtime.csproj" -c Release -f netcoreapp3.0 -p:TargetFrameworks=netcoreapp3.0 -o "$ToolsRoot/runtime"
if ($LASTEXITCODE -ne 0) { throw 'Runtime helper build failed' }
Copy-Item (Join-Path $PSScriptRoot 'scripts/wpf-designer/ProjectResources.cs') "$designer/XamlDesigner/ProjectResources.cs" -Force
Copy-Item (Join-Path $PSScriptRoot 'scripts/wpf-designer/PageClone.cs') "$designer/WpfDesign.Designer/Project/Controls/PageClone.cs" -Force
Copy-Item (Join-Path $PSScriptRoot 'scripts/wpf-designer/ToolboxView.xaml') "$designer/XamlDesigner/ToolboxView.xaml" -Force
$documentPath = "$designer/XamlDesigner/Document.cs"
$documentText = [IO.File]::ReadAllText($documentPath).Replace('XmlReader.Create(new StringReader(Text))', 'XmlReader.Create(new StringReader(ProjectResources.Prepare(Text)))')
$documentText = $documentText.Replace('OutlineRoot = DesignContext.RootItem.CreateOutlineNode();', 'ProjectResources.Apply(DesignContext.RootItem.View);' + [Environment]::NewLine + 'OutlineRoot = DesignContext.RootItem.CreateOutlineNode();')
[IO.File]::WriteAllText($documentPath, $documentText)
dotnet build "$designer/XamlDesigner/Demo.XamlDesigner.csproj" -c Release -f net10.0-windows -p:TargetFrameworks=net10.0-windows -o "$ToolsRoot/designer"
if ($LASTEXITCODE -ne 0) { throw 'Designer build failed' }
Write-Host "Installed tools: $ToolsRoot"
