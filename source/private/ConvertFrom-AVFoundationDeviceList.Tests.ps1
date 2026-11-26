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
    $functionName = 'ConvertFrom-AVFoundationDeviceList'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-AVFoundationDeviceList' {
    BeforeAll {
        $deviceList = @(
            '[AVFoundation indev @ 0x7f8a] AVFoundation video devices:'
            '[AVFoundation indev @ 0x7f8a] [0] FaceTime HD Camera'
            '[AVFoundation indev @ 0x7f8a] [1] Capture screen 0'
            '[AVFoundation indev @ 0x7f8a] [2] Capture screen 1'
            '[AVFoundation indev @ 0x7f8a] AVFoundation audio devices:'
            '[AVFoundation indev @ 0x7f8a] [0] MacBook Pro Microphone'
            '[in#0 @ 0x600] Error opening input: Input/output error'
        )
    }

    It 'Lists only the screens, skipping cameras and audio devices' {
        $screens = @(ConvertFrom-AVFoundationDeviceList -DeviceListOutput $deviceList)
        $screens.Count | Should -Be 2
        $screens.Name | Should -Be @('Capture screen 0','Capture screen 1')
    }

    It 'Keeps the device number ffmpeg needs, separate from the screen number' {
        $screens = @(ConvertFrom-AVFoundationDeviceList -DeviceListOutput $deviceList)
        $screens[0].DeviceIndex | Should -Be 1
        $screens[0].Index | Should -Be 0
        $screens[1].DeviceIndex | Should -Be 2
    }

    It 'Treats screen 0 as the main screen' {
        $screens = @(ConvertFrom-AVFoundationDeviceList -DeviceListOutput $deviceList)
        $screens[0].IsPrimary | Should -BeTrue
        $screens[1].IsPrimary | Should -BeFalse
    }

    It 'Returns nothing when there are no screens, such as without screen recording permission' {
        ConvertFrom-AVFoundationDeviceList -DeviceListOutput @('[AVFoundation indev @ 0x1] AVFoundation video devices:','[AVFoundation indev @ 0x1] [0] FaceTime HD Camera') | Should -BeNullOrEmpty
    }
}
