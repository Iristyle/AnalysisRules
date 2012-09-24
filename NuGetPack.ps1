param(
  [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
  [string]
  $APIKey = $Env:NUGET_API_KEY,

  [Parameter(Mandatory = $false, Position=0)]
  [string]
  [ValidateSet('Push','Pack')]
  $Operation = 'Push',

  [Parameter(Mandatory = $false, Position=1)]
  [string]
  $Source = $Env:NUGET_SOURCE_URL
)

if ([string]::IsNullOrEmpty($APIKey))
{
  throw 'Invalid Nuget API Key Specified!'
}

if ([string]::IsNullOrEmpty($Source))
{
  $Source = 'https://nuget.org/'
}


function Get-CurrentDirectory
{
  $thisName = $MyInvocation.MyCommand.Name
  [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}

function Get-NugetPath
{
  Write-Host "Executing Get-NugetPath"
  Get-ChildItem -Path (Get-CurrentDirectory) -Include 'nuget.exe' -Recurse |
    Select -ExpandProperty FullName -First 1
}

function Restore-Nuget
{
  Write-Host "Executing Restore-Nuget"
  $nuget = Get-NugetPath

  if ($nuget -ne $null)
  {
      &$nuget update -Self | Write-Host
      return $nuget
  }

  $nuget = Join-Path (Get-CurrentDirectory) 'nuget.exe'
  (New-Object Net.WebClient).DownloadFile('http://nuget.org/NuGet.exe', $nuget)

  return $nuget
}

function Invoke-Pack
{
  $currentDirectory = Get-CurrentDirectory
  Write-Host "Running against $currentDirectory"

  Get-ChildItem -Path $currentDirectory -Filter *.nuspec -Recurse |
    ? { $_.FullName -inotmatch 'packages' } |
    % {
      $csproj = Join-Path $_.DirectoryName ($_.BaseName + '.csproj')
      $cmdLine = if (Test-Path $csproj)
      {
        @('pack', $csproj, '-Prop', 'Configuration=Release', ' -Exclude',
          '**\*.CodeAnalysisLog.xml')
      }
      else { @('pack', $_) }

      &$script:nuget $cmdLine | Write-Host
    }
}

function Invoke-Push
{
 Get-ChildItem *.nupkg |
   % {
     Write-Host "Pushing to nuget source -> $Source"

     $params = @('push', $_, $APIKey)

     &$script:nuget push $_ $APIKey -s $Source | Write-Host
   }
}

$script:nuget = Restore-Nuget
del *.nupkg
Invoke-Pack
if ($operation -eq 'Push') { Invoke-Push }
del *.nupkg
