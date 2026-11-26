<#
    .SYNOPSIS
        Run a ModuleForge project's own PSScriptAnalyzer rules and report the results.

    .DESCRIPTION
        Runs whatever is in the project's root PSScriptAnalyzer folder against its source. The
        files in that folder decide what runs. If there are none, the script does nothing.

        Each of these is a rule set, with its own line in the report:
          - PSScriptAnalyzer\*.psd1      a settings file naming the rules to run
          - PSScriptAnalyzer\rules\*     a folder or .psm1 file containing custom rules

        This is additive to the default PSScriptAnalyzer lint, and never repeats it:
          - A settings file only runs the rules it names, in IncludeRules or Rules. Naming a default
            rule is the one way to run it here.
          - IncludeDefaultRules, CustomRulePath and RecurseCustomRulePath are ignored in settings
            files. Custom rules belong in the rules folder.
          - A PSScriptAnalyzerSettings.psd1 sitting beside a source file is not picked up.

        Scans source\functions, private, classes, enums and validationClasses, unlike the default
        lint, because a class anywhere in a module can matter as much as a function.

        Advisory only. Findings, and rule sets that could not run, are reported and never throw.
        A rule set that reports nothing is only shown as clean if it can be shown to have run:
        a misspelled rule name or a missing Enable = $true also produce zero findings.

        Custom rules are PowerShell code, and they run here with the access of whoever runs this
        script. The CI templates run it in a job with no write token for that reason.

    .EXAMPLE
        .\scripts\Invoke-MFProjectRules.ps1

        Run the project's rule sets, printing each finding with its line number.

    .EXAMPLE
        (.\scripts\Invoke-MFProjectRules.ps1).Report

        Run the project's rule sets, and show the same markdown report CI posts to a pull request.

    .EXAMPLE
        .\scripts\Invoke-MFProjectRules.ps1 -InstallPSScriptAnalyzer -ReportPath .\projectRules.md

        Install the latest PSScriptAnalyzer if there is anything to run, and save the report.

    .OUTPUTS
        [PSCustomObject] - HasRuleSets, ThreadStatus (active or closed), Report (markdown) and RuleSets

    .NOTES
        Author: Adrian Andersson
#>
[CmdletBinding()]
PARAM(
    #Root path of the project. Walks up from this script's directory to moduleForgeConfig.xml by default
    [Parameter()]
    [string]$ProjectPath,
    #Where to save the markdown report. Nothing is saved if this is omitted, or if there are no rule sets
    [Parameter()]
    [string]$ReportPath,
    #Install the latest PSScriptAnalyzer, only if there are rule sets to run. Used by the CI templates
    [Parameter()]
    [switch]$InstallPSScriptAnalyzer,
    #Maximum rows in each report table
    [Parameter()]
    [ValidateRange(1,100)]
    [int]$Top = 5
)

if(!$PSBoundParameters.ContainsKey('InformationAction'))
{
    $InformationPreference = 'Continue'
}

function Get-MFChildFolder
{
    #Case-insensitive folder probe, so this stays cross-platform safe
    PARAM([string]$Path,[string]$Name)
    Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
}

function Get-MFFindingKey
{
    #Identifies one finding, so the same parser note can be recognised in every rule set's results
    PARAM([object]$Finding)
    "$($Finding.ScriptPath)|$($Finding.Line)|$($Finding.RuleName)|$($Finding.Message)"
}

function Invoke-MFRuleSetScan
{
    #Runs one rule set over every source file, and turns the outcome into a status
    PARAM([hashtable]$RuleSet,[string[]]$SourceFile,[hashtable]$ParserNoise = @{})

    $findings = [System.Collections.Generic.List[object]]::new()
    try
    {
        $splat = $RuleSet.Splat
        foreach($file in $SourceFile)
        {
            #-ErrorAction Stop as a rule that throws is otherwise only a printed error and zero findings
            Invoke-ScriptAnalyzer -Path $file @splat -ErrorAction Stop | Sort-Object -Property Line | Where-Object {
                #Parser notes such as TypeNotFound come back with every rule set, but no rule set asked for them
                !$ParserNoise.ContainsKey((Get-MFFindingKey $_))
            } | ForEach-Object { $findings.Add($_) }
        }
    }
    catch
    {
        $RuleSet.Status = 'Failed'
        $RuleSet.Detail = ($_.Exception.Message -split "`r?`n")[0]
        return
    }

    $RuleSet.Findings = $findings.ToArray()
    if($findings.Count -ge 1)
    {
        $RuleSet.Status = 'Findings'
    }
    elseif($RuleSet.Unconfirmed)
    {
        $RuleSet.Status = 'Unconfirmed'
        $RuleSet.Detail = "no Enable = `$true for $($RuleSet.Unconfirmed -join ', ')"
    }
    else
    {
        $RuleSet.Status = 'Clean'
    }
}

function ConvertTo-MFTableCell
{
    #Rule and exception text is not ours, so stop it breaking the table
    PARAM([string]$Text)
    (($Text -replace '\|','\|') -replace '\s+',' ').Trim()
}

function New-MFReport
{
    PARAM([object[]]$RuleSet,[int]$Top,[string]$AnalyzerVersion,[string]$AnalyzerSource)

    #Matched by the Azure DevOps comment job to find this report's thread
    $marker = '<!-- moduleforge:project-rules -->'
    $title = '### 🧭 Project Rules'
    #The same runtime details as the Pester and PSScriptAnalyzer comments
    $footer = @(
        '### ℹ️ Runtime Info'
        "**PSScriptAnalyzer:** $AnalyzerVersion$(if($AnalyzerSource){" · $AnalyzerSource"})"
        "**PSVersion:** $($PSVersionTable.PSVersion.ToString()) $($PSVersionTable.PSEdition)"
        "**OS:** $($PSVersionTable.OS) $($PSVersionTable.Platform)"
        ''
        '_This comment was generated automatically by the CI pipeline._'
    ) -join "`n"

    if(!($RuleSet.Where{$_.Status -ne 'Clean'}))
    {
        $cleanNames = ($RuleSet.Name | ForEach-Object { '`{0}`' -f $_ }) -join ', '
        return @(
            $marker
            $title
            ''
            "✅ All rule sets clean: $cleanNames"
            ''
            $footer
            ''
        ) -join "`n"
    }

    $statusText = @{
        Clean = {'✅ Clean'}
        Findings = {'⚠️ Findings'}
        Unconfirmed = {param($item) "⚠️ May not have run: $(ConvertTo-MFTableCell $item.Detail)"}
        NotRun = {param($item) "❌ Not run: $(ConvertTo-MFTableCell $item.Detail)"}
        Failed = {param($item) "❌ Failed: $(ConvertTo-MFTableCell $item.Detail)"}
    }

    $sections = foreach($item in $RuleSet.Where{$_.Status -eq 'Findings'})
    {
        #With one rule its name adds nothing to the status table, so show what it found instead
        $byMessage = @($item.Findings.RuleName | Sort-Object -Unique).Count -eq 1
        $groupBy = if($byMessage){'Message'}else{'RuleName'}
        $topItems = $item.Findings | Group-Object -Property $groupBy | Sort-Object -Property @{Expression='Count';Descending=$true},'Name' | Select-Object -First $Top
        $topFiles = $item.Findings | Group-Object -Property 'ScriptName' | Sort-Object -Property @{Expression='Count';Descending=$true},'Name' | Select-Object -First $Top
        ''
        "#### $($item.Name)"
        ''
        "|$(if($byMessage){'Finding'}else{'Rule'})|Occurrence|"
        '|-|-|'
        $topItems.ForEach{ "|$(ConvertTo-MFTableCell $_.Name)|$($_.Count)|" }
        ''
        '|Filename|Findings|'
        '|-|-|'
        $topFiles.ForEach{ "|$($_.Name)|$($_.Count)|" }
    }

    @(
        $marker
        $title
        ''
        "_Your project's own standards. Advisory only._"
        ''
        '|Rule set|Type|Status|Findings|'
        '|-|-|-|-|'
        $RuleSet.ForEach{ "|$($_.Name)|$($_.Type)|$(& $statusText[$_.Status] $_)|$(if($_.Status -in 'NotRun','Failed'){'-'}else{@($_.Findings).Count})|" }
        $sections
        ''
        "_Up to $Top items per table. See the workflow output for line numbers._"
        ''
        $footer
        ''
    ) -join "`n"
}

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

$noRuleSets = [PSCustomObject]@{
    HasRuleSets = $false
    ThreadStatus = $null
    Report = $null
    RuleSets = @()
}

$rulesFolder = Get-MFChildFolder -Path $ProjectPath -Name 'PSScriptAnalyzer'
if(!$rulesFolder)
{
    Write-Verbose 'No PSScriptAnalyzer folder, nothing to run'
    return $noRuleSets
}

#Found first and run later, so a project with nothing to run never installs anything
$settingsFiles = @(Get-ChildItem -LiteralPath $rulesFolder.FullName -File | Where-Object { $_.Extension -eq '.psd1' })

$customRules = @()
$customRulesFolder = Get-MFChildFolder -Path $rulesFolder.FullName -Name 'rules'
if($customRulesFolder)
{
    $customRules = @(Get-ChildItem -LiteralPath $customRulesFolder.FullName | Where-Object {
        if($_.PSIsContainer)
        {
            Get-ChildItem -LiteralPath $_.FullName -File -Recurse | Where-Object { $_.Extension -in '.psm1','.psd1' }
        }
        else
        {
            $_.Extension -eq '.psm1'
        }
    })
}

if(($settingsFiles.Count + $customRules.Count) -lt 1)
{
    Write-Verbose 'No active files in the PSScriptAnalyzer folder, nothing to run'
    return $noRuleSets
}

$analyzerSource = 'already installed'
$analyzerImportVersion = $null
if($InstallPSScriptAnalyzer)
{
    #The shared installer pins PSScriptAnalyzer to BuildDependencies.psd1, as the other workflows do
    $sharedInstaller = Join-Path -Path $PSScriptRoot -ChildPath 'Install-MFBuildDependencies.ps1'
    if(Test-Path -LiteralPath $sharedInstaller)
    {
        $installed = & $sharedInstaller -ProjectPath $ProjectPath -Name PSScriptAnalyzer
        $analyzerImportVersion = $installed.ModuleVersion
        $analyzerSource = $installed.Description
    }
    else
    {
        #Only if there is something newer. Reinstalling the version a runner already has warns that it is in use
        $installed = Get-Module -ListAvailable -Name PSScriptAnalyzer | Sort-Object -Property Version -Descending | Select-Object -First 1
        if(!$installed -or $installed.Version -lt [version](Find-Module -Name PSScriptAnalyzer).Version)
        {
            Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck -Scope CurrentUser
        }
        $analyzerSource = 'latest from PSGallery'
    }
}
if(!(Get-Module -ListAvailable -Name PSScriptAnalyzer))
{
    throw 'PSScriptAnalyzer must be installed to run project rules. Use -InstallPSScriptAnalyzer to install it.'
}
if($analyzerImportVersion)
{
    #Exactly the version the installer resolved, so a newer copy elsewhere can't take its place
    Import-Module PSScriptAnalyzer -RequiredVersion $analyzerImportVersion -ErrorAction Stop
}
else
{
    Import-Module PSScriptAnalyzer
}
$analyzerVersion = (Get-Module PSScriptAnalyzer | Sort-Object -Property Version -Descending | Select-Object -First 1).Version.ToString()
$knownRules = @((Get-ScriptAnalyzerRule).RuleName)

$sourceFolders = 'functions','private','classes','enums','validationClasses'
$sourcePath = Get-MFChildFolder -Path $ProjectPath -Name 'source'
$sourceFiles = @(foreach($folder in $sourceFolders)
{
    $found = if($sourcePath){ Get-MFChildFolder -Path $sourcePath.FullName -Name $folder }
    if($found)
    {
        Get-ChildItem -LiteralPath $found.FullName -File -Recurse | Where-Object {
            $_.Extension -eq '.ps1' -and $_.Name -notmatch '\.(Tests|Skip)\.ps1$'
        } | ForEach-Object { $_.FullName }
    }
})
Write-Verbose "Source files: $($sourceFiles.Count)"

$ruleSets = [System.Collections.Generic.List[hashtable]]::new()

foreach($file in $settingsFiles)
{
    $ruleSet = @{ Name = $file.BaseName; Type = 'Settings'; Status = 'NotRun'; Detail = $null; Unconfirmed = @(); Findings = @(); Splat = $null }
    $ruleSets.Add($ruleSet)
    try
    {
        $settings = Import-PowerShellDataFile -LiteralPath $file.FullName -ErrorAction Stop
    }
    catch
    {
        $ruleSet.Detail = "unable to read $($file.Name)"
        continue
    }

    $ruleNames = @(@($settings.IncludeRules) + @(if($settings.Rules){ $settings.Rules.Keys }) | Where-Object { $_ } | Sort-Object -Unique)
    if($ruleNames.Count -lt 1)
    {
        $ruleSet.Detail = 'it does not name any rules'
        continue
    }

    #Exact names only. This catches a typo, a wildcard, or a PSScriptAnalyzer too old to have the rule
    $unknownRules = @($ruleNames.Where{ $_ -notin $knownRules })
    if($unknownRules)
    {
        $ruleSet.Detail = "$($unknownRules -join ', ') not found"
        continue
    }

    #Default-off rules need Enable, and PSScriptAnalyzer can't say which rules those are, so this only flags
    #the rule set if it finds nothing
    $ruleSet.Unconfirmed = @($ruleNames.Where{ !($settings.Rules -and $settings.Rules[$_] -and $settings.Rules[$_].Enable) })

    #An explicit rule list is what keeps the default rules out
    'IncludeDefaultRules','CustomRulePath','RecurseCustomRulePath'.ForEach{ $settings.Remove($_) }
    $settings.IncludeRules = [string[]]$ruleNames
    $ruleSet.Splat = @{ Settings = $settings }
}

foreach($item in $customRules)
{
    $ruleSets.Add(@{
        Name = $item.BaseName
        Type = 'Custom rules'
        Status = 'NotRun'
        Detail = $null
        Unconfirmed = @()
        Findings = @()
        #The empty Settings stops a settings file beside a source file bringing the default rules back
        Splat = @{ CustomRulePath = $item.FullName; RecurseCustomRulePath = $true; Settings = @{} }
    })
}

#PSScriptAnalyzer reports some parser notes, such as TypeNotFound for a class defined in another file, whatever
#rules run. A rule name that matches nothing returns only those notes, so they can be removed from each rule set
$parserNoise = @{}
if($ruleSets.Where{ $_.Splat })
{
    foreach($file in $sourceFiles)
    {
        Invoke-ScriptAnalyzer -Path $file -Settings @{ IncludeRules = @('MFNoRuleMatchesThisName') } -ErrorAction SilentlyContinue | ForEach-Object {
            $parserNoise[(Get-MFFindingKey $_)] = $true
        }
    }
}

foreach($ruleSet in $ruleSets)
{
    if($ruleSet.Splat)
    {
        Invoke-MFRuleSetScan -RuleSet $ruleSet -SourceFile $sourceFiles -ParserNoise $parserNoise
    }
    Write-Information "$($ruleSet.Name): $($ruleSet.Status) $(if($ruleSet.Detail){"- $($ruleSet.Detail)"}else{"($(@($ruleSet.Findings).Count))"})"
    $ruleSet.Findings.ForEach{ Write-Information "  $($_.ScriptName):$($_.Line) [$($_.RuleName)] $($_.Message)" }
}

$results = @($ruleSets | Sort-Object -Property { $_.Name } | ForEach-Object { [PSCustomObject]$_ })
$report = New-MFReport -RuleSet $results -Top $Top -AnalyzerVersion $analyzerVersion -AnalyzerSource $analyzerSource
if($ReportPath)
{
    $report | Out-File -FilePath $ReportPath -Encoding UTF8
}

[PSCustomObject]@{
    HasRuleSets = $true
    ThreadStatus = if($results.Where{$_.Status -ne 'Clean'}){'active'}else{'closed'}
    Report = $report
    RuleSets = $results
}
