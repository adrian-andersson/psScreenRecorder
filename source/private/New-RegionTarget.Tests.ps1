[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    foreach($dependency in @('New-CaptureTarget.ps1'))
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'New-RegionTarget'
    . $fileName

    $primary = New-CaptureTarget -Kind Monitor -Name 'Primary' -X 0 -Y 0 -Width 1920 -Height 1080 -IsPrimary $true
    $left = New-CaptureTarget -Kind Monitor -Name 'Left' -X -2560 -Y 0 -Width 2560 -Height 1440
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'New-RegionTarget' {
    It 'Rounds the size down to even numbers' {
        $region = New-RegionTarget -X 10 -Y 10 -Width 801 -Height 451 -Monitors $primary -Platform Windows
        $region.Width | Should -Be 800
        $region.Height | Should -Be 450
        $region.Name | Should -Be '800x450 at 10,10'
    }

    It 'Attaches the monitor the region fits inside, including one left of the primary' {
        (New-RegionTarget -X -2000 -Y 100 -Width 640 -Height 480 -Monitors $primary,$left -Platform Windows).Monitor.Name | Should -Be 'Left'
    }

    It 'Has no monitor when the region spans two' {
        (New-RegionTarget -X -100 -Y 100 -Width 640 -Height 480 -Monitors $primary,$left -Platform Linux).Monitor | Should -BeNullOrEmpty
    }

    It 'Puts the region on the main screen on macOS, which reports no sizes' {
        $screen = New-CaptureTarget -Kind Monitor -Name 'Main' -IsPrimary $true -DeviceIndex 1
        (New-RegionTarget -X 10 -Y 10 -Width 100 -Height 100 -Monitors $screen -Platform macOS).Monitor.Name | Should -Be 'Main'
    }

    It 'Throws for an area under 2 pixels' {
        { New-RegionTarget -X 0 -Y 0 -Width 1 -Height 100 } | Should -Throw '*at least 2 pixels*'
    }
}
