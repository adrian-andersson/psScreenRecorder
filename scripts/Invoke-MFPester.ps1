#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0' }
<#
    .SYNOPSIS
        Run Pester tests for a ModuleForge project with code coverage.

    .DESCRIPTION
        Locates the ModuleForge project root by walking up from the script's own directory,
        discovers test files, and runs Pester with code coverage enabled across all non-test
        function scripts.

        Test discovery:
          - source\functions and source\private are always discovered (the test-alongside-function
            convention - put a function's tests next to it).
          - If a root-level 'tests' folder exists (matched case-insensitively), it is ALSO
            discovered. This is an optional home for integration tests, or for anyone who prefers
            a separate tests folder.
          - Pass -TestPath to override discovery entirely with one or more explicit locations
            (useful for differentiating local vs CI test runs).

        Code coverage:
          - Measured against source\functions and source\private (the project's PowerShell logic).
            Deliberately excluded: classes, enums, validationClasses (Pester class coverage is
            unreliable) and bin, lib, resource (binaries and templates, not logic). The 'tests'
            folder is never added to coverage.
          - .Tests.ps1 and .Skip.ps1 files are always excluded from coverage measurement.
          - Additional filenames can be excluded via the ExcludeFromCoverage parameter.
          - Pass -SkipCodeCoverage to disable coverage entirely. Required on Constrained
            Language Mode systems, where Pester's coverage instrumentation cannot run.

        Sets the working directory to the project root before invoking Pester so that
        test files using the existing get-location convention resolve paths correctly.

        Does not import or depend on ModuleForge. Safe to run in a clean CI environment.

    .EXAMPLE
        .\scripts\Invoke-MFPester.ps1

        Run all Pester tests with code coverage from a clean environment. Auto-detects a
        root 'tests' folder if present.

    .EXAMPLE
        .\scripts\Invoke-MFPester.ps1 -ExcludeFromCoverage 'Get-Something.ps1'

        Run all tests, excluding the named file from code coverage metrics.

    .EXAMPLE
        .\scripts\Invoke-MFPester.ps1 -SkipCodeCoverage

        Run all tests without code coverage. Use this on Constrained Language Mode systems.

    .EXAMPLE
        .\scripts\Invoke-MFPester.ps1 -TestPath '.\tests\Integration'

        Run only the tests under .\tests\Integration, overriding auto-detection.

    .NOTES
        Author: Adrian Andersson
#>
[CmdletBinding()]
PARAM(
    #Filenames (not full paths) to exclude from code coverage measurement
    [Parameter()]
    [string[]]$ExcludeFromCoverage = @(),
    #Pester output verbosity level
    [Parameter()]
    [ValidateSet('None','Normal','Detailed','Diagnostic')]
    [string]$Verbosity = 'Detailed',
    #Explicit test discovery location(s). Overrides the default source\functions + tests auto-detection
    [Parameter()]
    [string[]]$TestPath,
    #Skip code coverage entirely. Required on Constrained Language Mode systems where coverage instrumentation cannot run
    [Parameter()]
    [switch]$SkipCodeCoverage
)

# Walk up from this script's directory to find moduleForgeConfig.xml
$searchPath = $PSScriptRoot
$root = $null
while($searchPath)
{
    if(Get-ChildItem -LiteralPath $searchPath -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'moduleForgeConfig.xml' })
    {
        $root = $searchPath
        break
    }
    $parent = Split-Path $searchPath -Parent
    if($parent -eq $searchPath){ break }
    $searchPath = $parent
}

if(-not $root)
{
    throw "Unable to locate 'moduleForgeConfig.xml' in '$PSScriptRoot' or any parent directory. Is this a ModuleForge project?"
}

Write-Verbose "Project root: $root"
$functionsPath = Join-Path $root 'source' 'functions'

if(!(Test-Path $functionsPath))
{
    throw "Functions folder not found at: $functionsPath"
}

$privatePath = Join-Path $root 'source' 'private'

# Resolve test discovery path(s)
if($TestPath)
{
    Write-Verbose "Explicit TestPath supplied, overriding auto-detection"
    $runPaths = $TestPath
}
else
{
    $runPaths = @($functionsPath)
    # source\private is always discovered too, so private tests can live alongside their function
    if(Test-Path $privatePath)
    {
        $runPaths += $privatePath
    }
    # Case-insensitive probe for a root-level 'tests' folder (cross-platform safe)
    $testsFolder = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'tests' } | Select-Object -First 1
    if($testsFolder)
    {
        Write-Verbose "Root 'tests' folder detected at: $($testsFolder.FullName) - adding to discovery"
        $runPaths += $testsFolder.FullName
    }
}
Write-Verbose "Test discovery paths: $($runPaths -join ', ')"

$pesterHashtable = @{
    Run    = @{Passthru = $true; Path = $runPaths}
    Output = @{Verbosity = $Verbosity}
}

if($SkipCodeCoverage)
{
    Write-Verbose 'SkipCodeCoverage set - code coverage disabled'
    $pesterHashtable.CodeCoverage = @{Enabled = $false}
}
else
{
    # Coverage spans source\functions and source\private (the project's PowerShell logic). Classes,
    # enums, validationClasses, bin, lib and resource are deliberately excluded - see header notes.
    $coverageFolders = @($functionsPath)
    if(Test-Path $privatePath){ $coverageFolders += $privatePath }
    $coveragePaths = (Get-ChildItem $coverageFolders -Filter '*.ps1' -Recurse).Where{
        $_.Name -notmatch '\.Tests\.ps1$' -and
        $_.Name -notmatch '\.Skip\.ps1$' -and
        $_.Name -notin $ExcludeFromCoverage
    }.FullName
    Write-Verbose "Coverage files: $($coveragePaths.Count)"
    $pesterHashtable.CodeCoverage = @{Enabled = $true; Path = $coveragePaths}
}

$pesterConfig = New-PesterConfiguration -hashtable $pesterHashtable

$previousLocation = Get-Location
try
{
    Set-Location $root
    Invoke-Pester -Configuration $pesterConfig
}
finally
{
    Set-Location $previousLocation
}
