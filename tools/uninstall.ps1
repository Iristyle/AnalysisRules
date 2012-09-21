param($installPath, $toolsPath, $package, $project)

Add-Type -AssemblyName 'Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'
$msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) | Select-Object -First 1
$solution = Get-Interface $dte.Solution ([EnvDTE80.Solution2])
$projectPath = ([IO.Path]::GetDirectoryName($project.FullName))

#remove custom properties
$installedProperties = @($package.Id, 'CodeAnalysisRuleSet', 'Ruleset',
  'GendarmeConfigFilename', 'GendarmeRuleset', 'GendarmeIgnoreFilename')

$msbuild.Xml.Properties |
  ? { $installedProperties -icontains $_.Name } |
  % {
    $_.Parent.RemoveChild($_)
    Write-Host "Removed property $($_.Name) from project file"
  }

#remove linked files
$physicalFiles = @('Settings.StyleCop','Properties\gendarme.ignore')
$physicalFiles |
  % { Remove-Item (Join-Path $projectPath $_) }

$paths = $physicalFiles + "`$($($package.Id))\CustomDictionary.xml")

$msbuild.Xml.Items |
  ? { $paths -icontains $_.Include } |
  % {
    $_.Parent.RemoveChild($_)
    Write-Host "Removed link to $($_.Include)"
  }

$project.Save($project.FullName)
