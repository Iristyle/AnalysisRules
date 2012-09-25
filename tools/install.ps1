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

function RemoveProperty($xml, $name)
{
  $xml.Properties |
    ? { $name -icontains $_.Name } |
    % {
      $_.Parent.RemoveChild($_)
      Write-Host "Removed property $($_.Name) from project file"
    }
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
$msbuild = [Microsoft.Build.Evaluation.ProjectCollection]::GlobalProjectCollection.GetLoadedProjects($project.FullName) |
  Select-Object -First 1

$editorConfigDest = Join-Path $solutionPath '.editorconfig'
if (!(Test-Path $editorconfigDest))
{
  $editorconfigSrc = Join-Path $toolsPath 'default.editorconfig'
  Copy-Item -Path $editorconfigSrc -Destination $editorConfigDest
}

#Add the CODE_ANALYSIS property to builds where appropriate
$msbuild.Xml.Properties |
  ? { $_.Name -ieq 'DefineConstants' } |
  % {
    $isDebug = ($_.Value -imatch '(^|;)DEBUG(;|$)') -or `
      ($_.Parent.Condition -imatch '== ''Debug\|')
    $isCodeAnalysis = $_.Value -imatch '(^|;)CODE_ANALYSIS(;|$)'

    if ((!$isDebug) -and (!$isCodeAnalysis))
      { $_.Value += ';CODE_ANALYSIS' }
  }

# Make the path to the targets file relative.
$projectUri = New-Object Uri("file://$($project.FullName)")
$targetUri = New-Object Uri("file://$($toolsPath)")
$relativePath = $projectUri.MakeRelativeUri($targetUri).ToString() `
  -replace [IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar

#update AnalysisRules relative path based on version
$msbuild.SetProperty($package.Id, $relativePath)

#make sure our WarningLevel is at 4 and we flag warnings as errors
$msbuild.SetProperty('WarningLevel', '4')

# for future use - mark specific compiler warnings as errors (by name)
# $msbuild.SetProperty('WarningsAsErrors', 'CS1234')

# Code Analysis MSBuild variables
# http://www.bryancook.net/2011/06/visual-studio-code-analysis-settings.html

#Assume that a build server runs FxCop differently and collects the output
#$msbuild.SetProperty('RunCodeAnalysis', '$(BuildingInsideVisualStudio)')
$msbuild.SetProperty('RunCodeAnalysis', 'True')
$msbuild.SetProperty('FxCopVs', '..\..\Team Tools\Static Analysis Tools\FxCop')

# This is how we could set a FxCop log file
# $msbuild.Xml.PropertyGroups |
#   % {
#     $outputPath = $_.Properties |
#       ? { $_.Name -eq 'OutputPath' }

#     if ($outputPath -ne $null)
#     {
#       $_.AddProperty('CodeAnalysisLogFile', '$(OutputPath)\FxCopLog.xml')
#     }
#   }


# clean up *all* existing variables should they exist
RemoveProperty $msbuild.Xml 'CodeAnalysisPath'

#FxCop is fickle - tell it where to find itself - order is critical! (last wins)
# http://geekswithblogs.net/terje/archive/2012/08/18/how-to-fix-the-ca0053-error-in-code-analysis-in.aspx
$fxCops = "`$(ProgramFiles)\Microsoft Fxcop 10.0",
  "`$(MSBuildProgramFiles32)\Microsoft Fxcop 10.0",
  # VS 2010
  "`$(VS100COMNTOOLS)`$(FxCopVs)",
  # VS 2012
  "`$(VS110COMNTOOLS)`$(FxCopVs)",
  # match up with current VS, but only defined inside VS
  # http://blogs.clariusconsulting.net/kzu/devenvdir-considered-harmful/
  "`$(DevEnvDir)`$(FxCopVs)"

$fxCops |
  % {
    # HACK: MsBuild API is wacky - have to add a property with junk name
    # then rename, otherwise, only one name goes in
    $fxCopPath = @{
      Name = 'fake' + [Guid]::NewGuid().ToString('n');
      Path = $_;
    }
    $msbuild.SetProperty($fxCopPath.Name, $fxCopPath.Path) | Out-Null
    return $fxCopPath
  } |
  #HACK: two separate iterations required for DTE to properly handle this
  % {
    Write-Host ("Hacking property $($_.Name) back to 'CodeAnalysisPath' and" +
      "setting conditional path to $($_.Path)")
    $fakeProperty = GetProperty $msbuild.Xml $_.Name
    $fakeProperty.Condition = "Exists('$($_.Path)')"
    $fakeProperty.Name = 'CodeAnalysisPath'
    # HACK: calling Save() here causes extra VS 'reload' dialogs
    # but for some reason allows all $fxCops to go in properly all the time
    #$msbuild.Save()
  }

#to use the above, it has to follow in the order
RemoveProperty $msBuild.Xml 'FxCopPath'
$msbuild.SetProperty('FxCopPath', '$(CodeAnalysisPath)')

#now tell it alternate rule directories (reversed from above - first wins)
#TODO: point at ASP.NET security rules! this generates CA0053 errors
#$msBuild.SetProperty('CodeAnalysisRuleDirectories',
#  (($fxCops[$fxCops.Count..0] | % { Join-Path $_ 'Rules' })  -join ';'))

#to use the above, it has to follow in the order
RemoveProperty $msBuild.Xml 'FxCopRulesPath'
$msBuild.SetProperty('FxCopRulesPath', '$(CodeAnalysisRuleDirectories)')

#convention that projects ending in .test or .tests get different rules
$lowerName = $project.Name.ToLower()
$isTest = $lowerName.EndsWith('.test') -or $lowerName.EndsWith('.tests')

#configure FxCop to run the appropriate ruleset file
if ($isTest)
{
  $ruleFile = 'FxCopRules.Test.ruleset'
  $ruleSet = 'Test'
}
else
{
  $ruleFile = 'FxCopRules.ruleset'
  $ruleSet = 'Standard'
}

$msbuild.SetProperty('CodeAnalysisRuleSet', "`$($($package.Id))\$ruleFile")
$msbuild.SetProperty('Ruleset', $ruleSet)

#for future tooling - let the project know that Gendarme is here
$msbuild.SetProperty('GendarmeConfigFilename',
  "`$($($package.Id))\gendarme-rules.xml")
$gendarmeRuleset = if ($isTest) { 'Test' } else { 'Standard' }
$msbuild.SetProperty('GendarmeRuleset', $gendarmeRuleset)
$msbuild.SetProperty('GendarmeIgnoreFilename', 'Properties\gendarme.ignore')

#ignore inline []s in attributes for xunit [Theory]
if ($isTest)
{
  $noWarn = (GetProperty $msbuild.Xml 'NoWarn').Value
  if ([string]::IsNullOrEmpty($noWarn))
    { $noWarn = '3016' }
  elseif ($noWarn -inotmatch '(^|,|\s)3016(,|\s|$)' )
    { $noWarn += ', 3016' }
  $msbuild.SetProperty('NoWarn', $noWarn)
}

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
  Write-Host "Modifying existing StyleCop Settings at $localSettingsPath"
  $xml = [Xml](Get-Content $localSettingsPath)
  $xml.StyleCopSettings.GlobalSettings.StringProperty |
    ? { $_.Name -eq 'LinkedSettingsFile' } |
    % {
      # If the reference was changed from Settings to Settings.Test
      # based on an incorrect match-up heuristic to determine 'Test' project
      $fileName = Split-Path $_.'#text' -Leaf
      $_.InnerText = Join-Path $relativePath $fileName
    }
  $xml.Save($localSettingsPath)
}
else
{
  Write-Host "Writing new StyleCop.Settings file to $localSettingsPath"
  $styleCopSettings = @"
<StyleCopSettings Version="4.3">
  <!-- WARNING: Only valid filenames for LinkedSettingsFile are:
    Settings.StyleCop
    Settings.Test.StyleCop -->
  <GlobalSettings>
    <StringProperty Name="LinkedSettingsFile">$parentSettingsPath</StringProperty>
    <StringProperty Name="MergeSettingsFiles">Linked</StringProperty>
  </GlobalSettings>
</StyleCopSettings>
"@
  $styleCopSettings | Out-File $localSettingsPath -Encoding UTF8
}

$item = AddOrGetItem $msbuild.Xml 'None' 'Settings.StyleCop'
$project.Save($project.FullName)
