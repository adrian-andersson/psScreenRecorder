<#
    .SYNOPSIS
        Install the modules a ModuleForge project needs to test and build, from its BuildDependencies.psd1.

    .DESCRIPTION
        Reads BuildDependencies.psd1 from the project root, in the format Install-PSResource -RequiredResourceFile
        reads, and installs the modules it lists. Prints the version of each module installed.

        Sources:
          - RequiredResourceFile  the versions and repositories pinned in the file. The default
          - PSGallery             the latest stable version of each module in the file, from PSGallery
          - PSGalleryPrerelease   the latest version of each, prereleases included, from PSGallery

        Pass -Name to install only some of the file's modules.

        Pass -ForTests in a Pester workflow. It installs what the testDependencies setting in
        moduleForgeConfig.xml asks for:
          - None                     nothing, so tests use the modules the runner already has
          - PesterAndScriptAnalyzer  Pester and PSScriptAnalyzer. The default, and used when the setting is missing
          - All                      Pester and PSScriptAnalyzer, plus everything else in the file except
                                     ModuleForge, which tests never need as they load from source. Mock anything
                                     else your code depends on where you can

        Pester and PSScriptAnalyzer are always installed for -ForTests unless the setting is None. If the file
        does not pin them, the latest comes from PSGallery with a warning.

        If the file is missing, or does not list a module named in -Name, that module is installed from
        PSGallery with a warning, so a project without the file still builds.

        Microsoft.PowerShell.PSResourceGet does all the installing, so it can't come from the file. PowerShell
        7.4 and newer include it. If it is missing or older than 1.0.0, it is installed with Install-Module.

        Does not import or depend on ModuleForge. Safe to run in a clean CI environment.

    .EXAMPLE
        .\scripts\Install-MFBuildDependencies.ps1

        Install every module in BuildDependencies.psd1, at the versions it pins.

    .EXAMPLE
        .\scripts\Install-MFBuildDependencies.ps1 -Name Pester

        Install only Pester, at the version the file pins.

    .EXAMPLE
        .\scripts\Install-MFBuildDependencies.ps1 -ForTests

        Install what the project's testDependencies setting asks for, before a Pester run.

    .EXAMPLE
        .\scripts\Install-MFBuildDependencies.ps1 -Source PSGalleryPrerelease -Name ModuleForge

        Install the newest ModuleForge from PSGallery, prereleases included, ignoring the version pinned in the file.

    .OUTPUTS
        [PSCustomObject] - Name and Version of each module installed

    .NOTES
        Author: Adrian Andersson
#>
[CmdletBinding()]
PARAM(
    #Where to install from. RequiredResourceFile uses the versions pinned in the file
    [Parameter()]
    [ValidateSet('RequiredResourceFile','PSGallery','PSGalleryPrerelease')]
    [string]$Source = 'RequiredResourceFile',
    #Only install these modules. Installs everything in the file by default
    [Parameter()]
    [string[]]$Name,
    #Install what the testDependencies setting in moduleForgeConfig.xml asks for, before a Pester run
    [Parameter()]
    [switch]$ForTests,
    #Root path of the project. Walks up from this script's directory to moduleForgeConfig.xml by default
    [Parameter()]
    [string]$ProjectPath,
    #Name of the dependency file in the project root
    [Parameter(DontShow)]
    [string]$DependencyFile = 'BuildDependencies.psd1'
)

#Modules every ModuleForge project needs, used when the file is missing
$essentialModules = 'ModuleForge','Pester','PSScriptAnalyzer'

if(!$ProjectPath)
{
    # Walk up from this script's directory to find moduleForgeConfig.xml
    $searchPath = $PSScriptRoot
    while($searchPath)
    {
        if(Get-ChildItem -LiteralPath $searchPath -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'moduleForgeConfig.xml' })
        {
            $ProjectPath = $searchPath
            break
        }
        $parent = Split-Path $searchPath -Parent
        if($parent -eq $searchPath){ break }
        $searchPath = $parent
    }
    if(!$ProjectPath)
    {
        throw "Unable to locate 'moduleForgeConfig.xml' in '$PSScriptRoot' or any parent directory. Is this a ModuleForge project?"
    }
}
Write-Verbose "Project root: $ProjectPath"

function Get-MFModuleReport
{
    #One line per module: the version to import, and where it came from, for the log and PR comments
    PARAM([string]$ModuleName,[string]$From,[string]$Pin,[object]$Version,[string]$Prerelease)
    $description = switch($From)
    {
        'Pinned' { "pinned $Pin in $DependencyFile" }
        'NotPinned' { "latest from PSGallery, not pinned in $DependencyFile" }
        'NoFile' { "latest from PSGallery, no $DependencyFile" }
        'PSGallery' { 'latest from PSGallery' }
        'PSGalleryPrerelease' { 'latest from PSGallery, prereleases included' }
        'Runner' { "the runner's own copy, as testDependencies is None" }
    }
    [PSCustomObject]@{
        Name = $ModuleName
        #Import-Module -RequiredVersion takes the version without any prerelease label
        ModuleVersion = if($Version){ "$Version" }else{ $null }
        Version = if($Version){ "$Version$(if($Prerelease){"-$Prerelease"})" }else{ 'not found' }
        Source = $From
        Description = $description
    }
}

$testsAll = $false
if($ForTests)
{
    if($Name)
    {
        throw '-ForTests and -Name can not be used together. -ForTests takes its list from moduleForgeConfig.xml'
    }
    $testDependencies = $null
    $configFile = Get-ChildItem -LiteralPath $ProjectPath -File | Where-Object { $_.Name -ieq 'moduleForgeConfig.xml' } | Select-Object -First 1
    if($configFile)
    {
        try{
            $testDependencies = (Import-Clixml -LiteralPath $configFile.FullName -ErrorAction Stop).testDependencies
        }catch{
            Write-Warning "Unable to read moduleForgeConfig.xml, so using the default testDependencies"
        }
    }
    if(!$testDependencies)
    {
        $testDependencies = 'PesterAndScriptAnalyzer'
    }
    Write-Verbose "testDependencies: $testDependencies"
    switch($testDependencies)
    {
        'None' {
            Write-Information 'testDependencies is None, so nothing is installed. Tests use the modules the runner already has' -InformationAction Continue
            #Still report what the runner has, so the workflow imports a known version and the comment can say so
            foreach($toolName in 'Pester','PSScriptAnalyzer')
            {
                $found = Get-Module -ListAvailable -Name $toolName | Sort-Object -Property Version -Descending | Select-Object -First 1
                Get-MFModuleReport -ModuleName $toolName -From 'Runner' -Version $found.Version -Prerelease $found.PrivateData.PSData.Prerelease
            }
            return
        }
        'PesterAndScriptAnalyzer' { $Name = 'Pester','PSScriptAnalyzer' }
        'All' { $testsAll = $true }
        default { throw "Unknown testDependencies value '$testDependencies' in moduleForgeConfig.xml. Use None, PesterAndScriptAnalyzer or All" }
    }
}

#PSResourceGet installs everything else, so it is bootstrapped with the older PowerShellGet
$resourceGet = Get-Module -ListAvailable -Name Microsoft.PowerShell.PSResourceGet | Sort-Object -Property Version -Descending | Select-Object -First 1
if(!$resourceGet -or $resourceGet.Version -lt [version]'1.0.0')
{
    Write-Warning 'Microsoft.PowerShell.PSResourceGet 1.0.0 or newer not found. Installing it from PSGallery'
    Install-Module -Name Microsoft.PowerShell.PSResourceGet -Repository PSGallery -Force -SkipPublisherCheck -Scope CurrentUser
}
Import-Module Microsoft.PowerShell.PSResourceGet

$dependencyPath = Get-ChildItem -LiteralPath $ProjectPath -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $DependencyFile } | Select-Object -First 1
$dependencies = @{}
if($dependencyPath)
{
    #A data file, so loading it can't run code
    $dependencies = Import-PowerShellDataFile -LiteralPath $dependencyPath.FullName
}else{
    Write-Warning "No $DependencyFile found in $ProjectPath. Installing from PSGallery without version pinning"
}

$wanted = if($Name){ $Name }elseif($dependencies.Count){ @($dependencies.Keys) }else{ $essentialModules }
if($testsAll)
{
    #Tests can't run without Pester, so never leave it to the file to remember it. Tests load from source,
    #so they never need the ModuleForge that builds the module
    $wanted = @(@('Pester','PSScriptAnalyzer') + $wanted | Sort-Object -Unique | Where-Object { $_ -ne 'ModuleForge' })
}

#Match the file's module names case-insensitively, as PowerShell does
$fileNames = @{}
$dependencies.Keys.ForEach{ $fileNames[$_.ToLower()] = $_ }

$fromFile = @{}
$fromGallery = [System.Collections.Generic.List[string]]::new()
#Why each module comes from where it does, in the order asked for
$moduleSources = [ordered]@{}
foreach($moduleName in $wanted)
{
    $fileName = $fileNames[$moduleName.ToLower()]
    if($Source -eq 'RequiredResourceFile' -and $fileName)
    {
        $fromFile[$fileName] = $dependencies[$fileName]
        $moduleSources[$fileName] = 'Pinned'
    }
    else
    {
        if($Source -eq 'RequiredResourceFile')
        {
            Write-Warning "$moduleName is not pinned in $DependencyFile. Installing the latest from PSGallery"
        }
        $galleryName = if($fileName){ $fileName }else{ $moduleName }
        $fromGallery.Add($galleryName)
        $moduleSources[$galleryName] = if($Source -ne 'RequiredResourceFile'){ $Source }elseif($dependencyPath){ 'NotPinned' }else{ 'NoFile' }
    }
}

if($fromFile.Count)
{
    Write-Verbose "Installing from $($DependencyFile): $($fromFile.Keys -join ', ')"
    Install-PSResource -RequiredResource $fromFile -TrustRepository -AcceptLicense -Quiet -ErrorAction Stop
}
foreach($moduleName in $fromGallery)
{
    Write-Verbose "Installing $moduleName from PSGallery"
    $gallerySplat = @{
        Name = $moduleName
        Repository = 'PSGallery'
        TrustRepository = $true
        AcceptLicense = $true
        Quiet = $true
        ErrorAction = 'Stop'
    }
    if($Source -eq 'PSGalleryPrerelease')
    {
        $gallerySplat.Prerelease = $true
    }
    Install-PSResource @gallerySplat
}

#Report the version each module resolved to. For a pinned module that is the newest installed copy the pin
#allows, which may not be the newest installed copy, so workflows import it by exact version
foreach($moduleName in $moduleSources.Keys)
{
    $from = $moduleSources[$moduleName]
    $pin = if($from -eq 'Pinned'){ $fromFile[$moduleName].version }
    $installedSplat = @{ Name = $moduleName; ErrorAction = 'SilentlyContinue' }
    if($pin){ $installedSplat.Version = $pin }
    $installed = Get-InstalledPSResource @installedSplat | Sort-Object -Property Version -Descending | Select-Object -First 1
    Get-MFModuleReport -ModuleName $moduleName -From $from -Pin $pin -Version $installed.Version -Prerelease $installed.Prerelease
}
