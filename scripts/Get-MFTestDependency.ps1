<#
    .SYNOPSIS
        Find the source files a Pester test needs, by file name, so the test can dot-source them.

    .DESCRIPTION
        Tests in a ModuleForge project load the functions they depend on from source, rather than importing
        the module. This finds each file by name anywhere under the source folder, so a test keeps working
        when files move between folders.

        Returns full paths in the order given, which is the order to load them in.

        Throws, rather than warns, when a name is:
          - not found under the source folder
          - found more than once, so the file a test would get depends on search order
          - listed more than once

        Run it with & so it can't change the test's variables, then dot-source what it returns:

            $dependencies = & $helperPath -SourcePath $sourcePath -Name 'Get-Thing.ps1','Set-Thing.ps1'
            $dependencies.ForEach{ . $_ }

        Does not import or depend on ModuleForge.

    .EXAMPLE
        & .\scripts\Get-MFTestDependency.ps1 -SourcePath .\source -Name 'Get-MFFolderItems.ps1'

        Return the full path of Get-MFFolderItems.ps1, wherever it is under source.

    .OUTPUTS
        [string] - The full path of each file, in the order given

    .NOTES
        Author: Adrian Andersson
#>
[CmdletBinding()]
[OutputType([string])]
PARAM(
    #The project's source folder
    [Parameter(Mandatory)]
    [string]$SourcePath,
    #File names to find anywhere under the source folder, such as Get-Thing.ps1. Returned in this order
    [Parameter(Mandatory)]
    [string[]]$Name
)

$listedTwice = @($Name | Group-Object | Where-Object { $_.Count -gt 1 })
if($listedTwice)
{
    throw "Dependencies listed more than once: $($listedTwice.Name -join ', ')"
}

if(!(Test-Path -LiteralPath $SourcePath))
{
    throw "Source folder not found: $SourcePath"
}

#File names match case-insensitively, as they do on Windows, so a test behaves the same on every platform
$sourceFiles = @{}
Get-ChildItem -LiteralPath $SourcePath -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $key = $_.Name.ToLower()
    if(!$sourceFiles.ContainsKey($key)){ $sourceFiles[$key] = [System.Collections.Generic.List[string]]::new() }
    $sourceFiles[$key].Add($_.FullName)
}

foreach($fileName in $Name)
{
    $found = $sourceFiles[$fileName.ToLower()]
    if(!$found)
    {
        throw "Dependency $fileName not found under $SourcePath"
    }
    if($found.Count -gt 1)
    {
        throw "Dependency $fileName found more than once under $SourcePath, so which one loads is unclear: $($found -join ', ')"
    }
    $found[0]
}
