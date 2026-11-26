[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#The overlay itself is driven for real in Initialize-ScreenRecorderNative.Tests.ps1, on a Windows desktop
BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'New-CaptureTarget.ps1'
        'New-RegionTarget.ps1'
        'Get-CaptureTarget.ps1'
        'Invoke-NativeRegionSelection.ps1'
        'Invoke-SlopSelection.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Select-ScreenRegion'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Select-ScreenRegion' {
    BeforeEach {
        Mock Get-CaptureTarget { New-CaptureTarget -Kind Monitor -Name 'Primary' -X 0 -Y 0 -Width 1920 -Height 1080 -IsPrimary $true -DeviceIndex 1 }
        Mock Invoke-NativeRegionSelection { ,[int[]]@(100,50,401,301) }
        Mock Invoke-SlopSelection { ,[int[]]@(100,50,401,301) }
        Mock Get-Command { [PSCustomObject]@{ Source = '/usr/bin/slop' } } -ParameterFilter { $Name -eq 'slop' }
    }

    It 'Returns a region target for what was selected, rounded to even, on its monitor' -Skip:$IsMacOS {
        $region = Select-ScreenRegion
        $region.Kind | Should -Be 'Region'
        $region.X | Should -Be 100
        $region.Width | Should -Be 400
        $region.Height | Should -Be 300
        $region.Monitor.Name | Should -Be 'Primary'
    }

    It 'Uses the overlay on Windows' -Skip:(!$IsWindows) {
        $null = Select-ScreenRegion
        Should -Invoke Invoke-NativeRegionSelection -Times 1 -Exactly
    }

    It 'Uses slop on Linux' -Skip:(!$IsLinux) {
        $null = Select-ScreenRegion
        Should -Invoke Invoke-SlopSelection -Times 1 -Exactly
    }

    It 'Throws, saying how to install it, when slop is missing on Linux' -Skip:(!$IsLinux) {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'slop' }
        { Select-ScreenRegion } | Should -Throw '*slop*not installed*'
    }

    It 'Throws on macOS, pointing to -Rectangle' -Skip:(!$IsMacOS) {
        { Select-ScreenRegion } | Should -Throw '*-Rectangle*'
    }

    It 'Returns nothing, with a warning, when cancelled' -Skip:$IsMacOS {
        Mock Invoke-NativeRegionSelection {}
        Mock Invoke-SlopSelection {}
        Mock Write-Warning {}
        Select-ScreenRegion | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*No area*' }
    }
}

Describe 'Invoke-SlopSelection' -Skip:$IsWindows {
    BeforeAll {
        #A stand-in slop, first on PATH, that prints what the real one would, or fails as a cancel does
        $fakeBin = Join-Path -Path $TestDrive -ChildPath 'bin'
        $null = New-Item -ItemType Directory -Path $fakeBin -Force
        $fakeSlop = Join-Path -Path $fakeBin -ChildPath 'slop'
        Set-Content -LiteralPath $fakeSlop -Value @('#!/bin/sh','if [ -n "$PSSR_SLOP_CANCEL" ]; then exit 1; fi','echo "12 34 640 480"')
        chmod +x $fakeSlop
        $savedPath = $env:PATH
        $env:PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
    }
    AfterAll {
        $env:PATH = $savedPath
        $env:PSSR_SLOP_CANCEL = $null
    }

    It 'Returns x, y, width and height' {
        Invoke-SlopSelection | Should -Be @(12,34,640,480)
    }

    It 'Returns nothing when cancelled' {
        $env:PSSR_SLOP_CANCEL = '1'
        Invoke-SlopSelection | Should -BeNullOrEmpty
        $env:PSSR_SLOP_CANCEL = $null
    }
}
