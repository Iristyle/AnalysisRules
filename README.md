# AnalysisRules

This project uses NuGet to distribute custom analysis and style rules, so that
consistency across projects can be mandated (and so that the rules may be
easily updated over time).  The major players are:

* [EditorConfig][EditorConfig] file line ending / spacing settings
* [StyleCop][StyleCop] settings for source style, like linting
* [FxCop][FxCop] aka `Code Analysis` settings for static analysis violations
* [Gendarme][Gendarme] settings for static analysis violations

[EditorConfig]: http://editorconfig.org/
[StyleCop]: stylecop.codeplex.com
[FxCop]: http://msdn.microsoft.com/en-us/library/dd264939(v=VS.100).aspx
[Gendarme]: http://www.mono-project.com/Gendarme

## Installation

To ensure that your project is modified correctly, this package should only be
installed from within Visual Studio using either the Nuget package manager
dialog or the package manager console.

The simplest way to install in package manager console for all projects is:

```powershell
Get-Project -All | % { Install-Package -ProjectName $_.Name -Id AnalysisRules }
```

Where `AnalysisRules` is the name of the published package.

### Updating

Additional updates should generally be performed in the same manner, as relative
paths to the package assets are written to the `.csproj` files.
git

### What does it modify?

Well, the installation script modifies the `.csproj` files to safely include
all relevant files.  The installation has a basic heuristic that detects test
projects and varies the configuration accordingly.

* For FxCop - tweaks to [CodeAnalysis settings][ca-settings] and ruleset config
    * `CodeAnalysisPath` is configured to work properly on VS2012, VS2010 or
    on a build server where FxCop may be in it's own directory. It defaults to
    looking in this order as the project loads

    ```plaintext
    $(DevEnvDir) - only works in current VS
    $(VS110COMNTOOLS) - VS 2012
    $(VS100COMNTOOLS) - VS 2010
    $(MSBuildProgramFiles32)\Microsoft Fxcop 10.0
    $(ProgramFiles)\Microsoft Fxcop 10.0
    ```

    * `CodeAnalysisRuleSet` sets to `FxCopRulesTest.ruleset` or
    `FxCopRules.ruleset` based on the project
    * `Ruleset` is either `Standard` or `Test`
    * `CODE_ANALYSIS` constant is set in `DefineConstants` for any projects
    that are not DEBUG
    * `CodeAnalysisDictionary` is linked to `CustomDictionary.xml` in this pkg
    * `FxCopPath` and `FxCopRulesPath` are set like `CodeAnalysisPath` and
    `CodeAnalysisRuleSet` for backward / cmd line compatibility
    * `RunCodeAnalysis` is set to `True` for the project
* For StyleCop
    * `Settings.StyleCop` is copied to the project directory, and links back to
    the file shipped in this package - varying based on the test heuristic
    * Individual project overrides may be placed in this Settings.StyleCop file
    as long as the link back to package file is maintained
* For Gendarme
    * `GendarmeConfigFilename` is set to the `gendarme-rules.xml` file shipping
    with this package
    * `GendarmeRuleset` is set to `Standard` or `Test` as appropriate
    * A `gendarme.ignore` file is copied to the projects `Properties` folder
    with some samples on how to ignore items for the particular project
* For EditorConfig
    * The `.editorconfig` file is copied into solution path IFF it isn't there
    * The settings use a 2 space (no TAB) indent with `CRLF` line endings

[ca-settings]: http://www.bryancook.net/2011/06/visual-studio-code-analysis-settings.html

## Creating Your Own Variations

This package serves as a basic blueprint, but you might not agree with our
selections.

Create a fork of this repo, configure the rules as you see fit, and publish
with the basic scaffolding we prescribe.

To push the package, from the source directory, using Powershell

```powershell
.\NuGetPack.ps1 -APIKey $yourApiKey -Source https://yournuget.com
```

##TODO

* Test / Expose dependencies through NuGet and ensure project props compatible
    * [Gendarme][Gendarme-tool] - Can kick off Gendarme from MSBuild
    * FxCop - currently no easy way to get FxCop installed outside of VS
    - seems like something for Chocolatey, but would be better to concoct a
    Nuget tool package that lives in a sibling directory IMHO
    * [ASP.NET security FXCop rules][sec-rules] - no means of distro right now
    * [StyleCop][StyleCop-tool] - provides all the MSBuild hooks
* Double-check that this runs OK under Jenkins - keep good on promises, right?
* Provide a system for project specific FxCop rule overloads
* Basic build server install instructions
* Include new [VS2012 rules][vs2012-rules]

[Gendarme-tool]: https://github.com/Iristyle/GendarmeMsBuild
[StyleCop-tool]: http://nuget.org/packages/StyleCop.MSBuild
[sec-rules]: http://fxcopaspnetsecurity.codeplex.com/
[vs2012-rules]: http://msdn.microsoft.com/en-us/library/ff977212.aspx
