param($installPath, $toolsPath, $package, $project)

#recursive search project for a given file name and return its project relative path
function Get-RelativeFilePath
{
  param($projectItems, $fileName)

  $match = $projectItems | ? { $_.Name -eq $fileName } |
      Select -First 1

  if ($null -ne $match) { return $match.Name }

  $projectItems | ? { $_.Kind -eq '{6BB5F8EF-4483-11D3-8BCF-00C04F8EC28C}' } |
    % {
        $match = Get-RelativeFilePath $_.ProjectItems $fileName
        if ($null -ne $match)
        {
            return (Join-Path $_.Name $match)
        }
    }
}

function AddOrGetItem($xml, $type, $path)
{
  $include = $xml.Items |
      ? { $_.Include -ieq $path } |
      Select-Object -First 1

  if ($include -ne $null) { return $include }

  Write-Host "Adding item of type $type to $path."
  return $xml.AddItem($type, $path)
}

function RemoveItem($xml, $paths)
{
  $msbuild.Xml.Items |
    ? { $paths -icontains $_.Include } |
    % {
      $_.Parent.RemoveChild($_)
      Write-Host "Removed $($_.Include)"
    }
}

function SetItemMetadata($item, $name, $value)
{
  $match = $item.Metadata |
    ? { $_.Name -ieq $name } |
    Select-Object -First 1

  if ($match -eq $null)
  {
    [Void]$item.AddMetadata($name, $value)
    Write-Host "Added metadata $name"
  }
  else { $match.Value = $value }
}

function GetProperty($xml, $name)
{
   $xml.Properties |
    ? { $_.Name -ieq $name } |
    Select-Object -First 1
}

function SetProperty($xml, $name, $value)
{
  $property = GetProperty $xml $name

  if ($property -eq $null)
  {
    [Void]$xml.AddProperty($name, $value)
    Write-Host "Added property $name"
  }
  else { $property.Value = $value }
}

#TODO - don't think we have to incorporate these values
# <RunCodeAnalysis>false</RunCodeAnalysis> <!-- by default, do not also run VS code analysis / Gendarme project specific analysis -->
# <!-- VS will set this by itself, but outside of VS, we need to set to false-->
# <BuildingInsideVisualStudio Condition="$(BuildingInsideVisualStudio) == ''">false</BuildingInsideVisualStudio>

#solution info
$solution = Get-Interface $dte.Solution ([EnvDTE80.Solution2])
$solutionPath = [IO.Path]::GetDirectoryName($solution.FileName)
$projectPath = ([IO.Path]::GetDirectoryName($project.FullName))

Add-Type -AssemblyName 'Microsoft.Build, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'

#http://msdn.microsoft.com/en-us/library/microsoft.build.evaluation.project
#http://msdn.microsoft.com/en-us/library/microsoft.build.construction.projectrootelement
#http://msdn.microsoft.com/en-us/library/microsoft.build.construction.projectitemelement
$msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) | Select-Object -First 1

#Add the CODE_ANALYSIS property to any constants that aren't defined DEBUG
$msbuild.Xml.Properties |
  ? { ($_.Name -ieq 'DefineConstants') -and ($_.Value -inotmatch 'DEBUG') `
    -and ($_.Value -inotmatch 'CODE_ANALYSIS') } |
  % { $_.Value += ';CODE_ANALYSIS' }

# Make the path to the targets file relative.
$projectUri = New-Object Uri("file://$($project.FullName)")
$targetUri = New-Object Uri("file://$($toolsPath)")
$relativePath = $projectUri.MakeRelativeUri($targetUri).ToString() `
  -replace [IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar

#update AnalysisRules relative path based on version
SetProperty $msbuild.Xml $package.Id $relativePath

#make sure our WarningLevel is at 4
SetProperty $msbuild.Xml 'WarningLevel' '4'

#Assume that a build server runs FxCop differently and collects the output
SetProperty $msbuild.Xml 'RunCodeAnalysis' '$(BuildingInsideVisualStudio)'

#convention that projects ending in .test or .tests get different rules
$lowerName = $project.Name.ToLower()
$isTest = $lowerName.EndsWith('.test') -or $lowerName.EndsWith('.tests')

#configure FxCop to run the appropriate ruleset file
$ruleFile = if ($isTest) { 'FxCopRules.Test.ruleset' }
else { 'FxCopRules.ruleset' }
SetProperty $msbuild.Xml 'CodeAnalysisRuleSet' `
  "`$(MSBuildThisFileDirectory)\$ruleFile"

#ruleset name is 'FxCop Rules' in both files
SetProperty $msbuild.Xml 'Ruleset' 'FxCop Rules'

#for future tooling - let the project know that Gendarme is here
SetProperty $msbuild.Xml 'GendarmeConfigFilename' "`$($($package.Id))\gendarme-rules.xml"
$gendarmeRuleset = if ($isTest) { 'Test' } else { 'Standard' }
SetProperty $msbuild.Xml 'GendarmeRuleset' $gendarmeRuleset
SetProperty $msbuild.Xml 'GendarmeIgnoreFilename' 'Properties\gendarme.ignore'

#ignore inline []s in attributes for xunit [Theory]
if ($isTest)
{
  $noWarn = GetProperty $msbuild.Xml 'NoWarn'
  $noWarn = if ([string]::IsNullOrEmpty($noWarn)) { '3016' }
  else { ', 3016' }
  SetProperty $msbuild.Xml 'NoWarn' $noWarn
}

#TODO: not sure if we should push these bits along somehow anymore
# <FxCopPath>$(ToolsPath)\FxCop-10.0</FxCopPath>
# <FxCopRulesPath>$(ToolsPath)\FxCop-10.0\Rules</FxCopRulesPath>
# <CodeAnalysisRuleDirectories>$(FxCopRulesPath)</CodeAnalysisRuleDirectories>

#incorporate CustomDictionary in the project
$dictionaryPath = "`$($($package.Id))\CustomDictionary.xml"
$item = AddOrGetItem $msbuild.Xml 'CodeAnalysisDictionary' $dictionaryPath
SetItemMetadata $item 'Link' 'Properties\CustomDictionary.xml'

#write an xml file for the stylecop settings
$parentSettingsPath = if ($isTest) { "$relativePath\Settings.Test.StyleCop" }
  else { "$relativePath\Settings.StyleCop" }

$localSettingsPath = Join-Path $projectPath 'Settings.StyleCop'

#if file exists it may have rule overrides
if (Test-Path $localSettingsPath)
{
  $xml = [Xml](Get-Content $localSettingsPath)
  $styleCopSettings.StyleCopSettings.GlobalSettings.StringProperty |
    ? { $_.Name -eq 'LinkedSettingsFile' } |
    % { $_.'#text' = $parentSettingsPath }
}
else
{
  $styleCopSettings = @"
<StyleCopSettings Version="4.3">
  <GlobalSettings>
    <StringProperty Name="LinkedSettingsFile">$parentSettingsPath</StringProperty>
    <StringProperty Name="MergeSettingsFiles">Linked</StringProperty>
  </GlobalSettings>
</StyleCopSettings>
"@
  $styleCopSettings | Out-File $localSettingsPath
}

$item = AddOrGetItem $msbuild.Xml 'None' 'Settings.StyleCop'
SetItemMetadata $item 'Link' 'Properties\Settings.StyleCop'

$project.Save($project.FullName)
