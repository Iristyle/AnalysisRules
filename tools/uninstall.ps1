param($installPath, $toolsPath, $package, $project)

Add-Type -AssemblyName 'Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'
$msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) | Select-Object -First 1
$solution = Get-Interface $dte.Solution ([EnvDTE80.Solution2])
$projectPath = ([IO.Path]::GetDirectoryName($project.FullName))

#remove custom properties
#assumption is if we turn this off, we don't want do anything code analysis
#anymore
$installedProperties = @($package.Id, 'RunCodeAnalysis', 'FxCopVs',
  'CodeAnalysisRuleSet', 'CodeAnalysisPath', 'Ruleset',
  'FxCopPath', 'FxCopRulesPath',
  'GendarmeConfigFilename', 'GendarmeRuleset', 'GendarmeIgnoreFilename')
#leave NoWarn 3016 on test projects b/c we don't know if it was there already

$msbuild.Xml.Properties |
  ? { $installedProperties -icontains $_.Name } |
  % {
    $_.Parent.RemoveChild($_)
    Write-Host "Removed property $($_.Name) from project file"
  }

#remove linked files
$physicalFiles = @('Settings.StyleCop')
$physicalFiles |
  % { Remove-Item (Join-Path $projectPath $_) }

$paths = $physicalFiles + "`$($($package.Id))\CustomDictionary.xml"

$msbuild.Xml.Items |
  ? { $paths -icontains $_.Include } |
  % {
    $_.Parent.RemoveChild($_)
    Write-Host "Removed link to $($_.Include)"
  }

$project.Save($project.FullName)
