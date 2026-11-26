<#
    Build test: checks the module Build and Release PUBLISHED, once it is installed, not the source.

    Unit tests load your functions straight from source/, so they can't see what the build changes: the
    manifest's export lists, the compiled .psm1, and how the package installs. This checks the installed
    module exports every public function in source/functions and every alias declared there, and nothing else.
    It reads the source itself rather than asking ModuleForge, so a build bug can't hide itself.

    The Build Test workflow (GitHub) or pipeline (Azure DevOps) installs the version Build and Release just
    published, then runs every *.Tests.ps1 in this folder. Add your own black-box tests in more files here,
    calling your commands the way a user would.

    If a .mfignore file leaves some of source/functions out of the build, those functions are reported missing.
    Remove them from the expected list below, or skip this file.

    To run it locally, build the module and put the build folder first on PSModulePath:
        Build-MFProject -Version 0.0.1
        $env:PSModulePath = "$(Resolve-Path ./build)$([IO.Path]::PathSeparator)$env:PSModulePath"
        Invoke-Pester ./buildTest
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeDiscovery{
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleName = (Import-Clixml -Path (Join-Path -Path $projectRoot -ChildPath 'moduleForgeConfig.xml')).moduleName

    #What the source says should be public: top-level functions in source/functions, their [Alias()] names,
    #and aliases made with a literal Set-Alias or New-Alias outside a function
    $sourceFunctions = [System.Collections.Generic.List[string]]::new()
    $sourceAliases = [System.Collections.Generic.List[string]]::new()
    $functionsFolder = Join-Path -Path $projectRoot -ChildPath 'source' -AdditionalChildPath 'functions'
    $files = Get-ChildItem -Path $functionsFolder -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.Tests.ps1' }
    foreach($file in $files)
    {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        foreach($function in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        {
            $parent = $function.Parent
            while($parent -and $parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst]){ $parent = $parent.Parent }
            if($parent){ continue }
            $sourceFunctions.Add($function.Name)
            $aliasAttributes = $function.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -in 'Alias','AliasAttribute','System.Management.Automation.AliasAttribute' }
            foreach($argument in $aliasAttributes.PositionalArguments)
            {
                $argument.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value.ForEach{ $sourceAliases.Add($_) }
            }
        }
        $aliasCommands = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -in 'Set-Alias','New-Alias','sal','nal' }, $true)
        foreach($command in $aliasCommands)
        {
            $parent = $command.Parent
            while($parent -and $parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst]){ $parent = $parent.Parent }
            if($parent){ continue }
            $name = [System.Management.Automation.Language.StaticParameterBinder]::BindCommand($command, $true).BoundParameters['Name'].ConstantValue
            if($name -is [string]){ $sourceAliases.Add($name) }
        }
    }
    $functions = @($sourceFunctions | Sort-Object -Unique | ForEach-Object { @{ Name = $_ } })
    $aliases = @($sourceAliases | Sort-Object -Unique | ForEach-Object { @{ Name = $_ } })
}

BeforeAll{
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleName = (Import-Clixml -Path (Join-Path -Path $projectRoot -ChildPath 'moduleForgeConfig.xml')).moduleName
    #Files in ScriptsToProcess load as modules too, so -PassThru can return more than one
    $imported = Import-Module -Name $moduleName -Force -PassThru -ErrorAction Stop
    $module = $imported | Where-Object { $_.Name -eq $moduleName } | Select-Object -First 1
    $manifest = Import-PowerShellDataFile -Path (Join-Path -Path $module.ModuleBase -ChildPath "$moduleName.psd1")

    #A DefaultCommandPrefix renames exported functions, Get-Thing becoming Get-<Prefix>Thing. Aliases keep their names
    function Get-ExportedFunctionName
    {
        param([string]$Name)
        if(!$module.Prefix){ return $Name }
        if($Name -match '^([^-]+)-(.+)$'){ return "$($Matches[1])-$($module.Prefix)$($Matches[2])" }
        "$($module.Prefix)$Name"
    }
}

Describe 'Published module <moduleName>' -ForEach @{ moduleName = $moduleName; functionCount = $functions.Count; aliasCount = $aliases.Count } {
    It 'Imports' {
        $module | Should -Not -BeNullOrEmpty
    }

    It 'Is the version its manifest says' {
        $module.Version | Should -Be ([version]$manifest.ModuleVersion)
    }

    Context 'Functions from source/functions' {
        It 'Exports <Name>' -ForEach $functions -AllowNullOrEmptyForEach {
            $module.ExportedFunctions.Keys | Should -Contain (Get-ExportedFunctionName -Name $Name)
        }

        It 'Exports no other functions' {
            $module.ExportedFunctions.Count | Should -Be $functionCount
        }
    }

    Context 'Aliases declared in source/functions' {
        It 'Exports <Name>' -ForEach $aliases -AllowNullOrEmptyForEach {
            $module.ExportedAliases.Keys | Should -Contain $Name
            #The alias has to point at something, or calling it fails
            $module.ExportedAliases[$Name].Definition | Should -Not -BeNullOrEmpty
        }

        It 'Exports no other aliases' {
            $module.ExportedAliases.Count | Should -Be $aliasCount
        }
    }
}

AfterAll{
    $imported | Remove-Module -Force -ErrorAction SilentlyContinue
}
