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
    $functionName = 'Select-CaptureBackend'
    . $fileName

    $windowsSources = @('gfxcapture','ddagrab','gdigrab')
    $monitor = New-CaptureTarget -Kind Monitor -X 0 -Y 0 -Width 1920 -Height 1080
    $window = New-CaptureTarget -Kind Window -Handle 1234
    $regionInMonitor = New-CaptureTarget -Kind Region -X 10 -Y 10 -Width 100 -Height 100 -Monitor $monitor
    $regionAcrossMonitors = New-CaptureTarget -Kind Region -X 1800 -Y 10 -Width 400 -Height 100
    $synthetic = New-CaptureTarget -Kind Synthetic -Width 640 -Height 360
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Select-CaptureBackend' {
    Context 'Choosing on Windows' {
        It 'Prefers gfxcapture for a <Kind>' -ForEach @(
            @{ Kind = 'monitor' }
            @{ Kind = 'window' }
            @{ Kind = 'region' }
        ) {
            $target = switch($Kind){ 'monitor' { $monitor } 'window' { $window } 'region' { $regionInMonitor } }
            Select-CaptureBackend -Target $target -AvailableSources $windowsSources -Platform Windows | Should -Be 'gfxcapture'
        }

        It 'Uses ddagrab, without gfxcapture, when there is one monitor' {
            Select-CaptureBackend -Target $monitor -AvailableSources 'ddagrab','gdigrab' -MonitorCount 1 -Platform Windows | Should -Be 'ddagrab'
        }

        It 'Skips ddagrab when there are several monitors, as its numbering is not confirmed' {
            Select-CaptureBackend -Target $monitor -AvailableSources 'ddagrab','gdigrab' -MonitorCount 2 -Platform Windows | Should -Be 'gdigrab'
        }

        It 'Never uses ddagrab for a window' {
            Select-CaptureBackend -Target $window -AvailableSources 'ddagrab','gdigrab' -Platform Windows | Should -Be 'gdigrab'
        }

        It 'Uses gdigrab for a region spanning monitors' {
            Select-CaptureBackend -Target $regionAcrossMonitors -AvailableSources $windowsSources -Platform Windows | Should -Be 'gdigrab'
        }

        It 'Throws when the build has no Windows capture source' {
            { Select-CaptureBackend -Target $monitor -AvailableSources @() -Platform Windows } | Should -Throw '*no screen capture source*'
        }
    }

    Context 'Choosing on macOS and Linux' {
        It 'Uses avfoundation on macOS' {
            Select-CaptureBackend -Target $monitor -AvailableSources 'avfoundation' -Platform macOS | Should -Be 'avfoundation'
        }

        It 'Uses x11grab on Linux' {
            Select-CaptureBackend -Target $monitor -AvailableSources 'x11grab','kmsgrab' -Platform Linux | Should -Be 'x11grab'
        }

        It 'Throws on Linux without x11grab' {
            { Select-CaptureBackend -Target $monitor -AvailableSources 'kmsgrab' -Platform Linux } | Should -Throw '*x11grab*'
        }
    }

    Context 'Synthetic targets' {
        It 'Always uses synthetic for a synthetic target, whatever the platform has' {
            Select-CaptureBackend -Target $synthetic -AvailableSources @() -Platform Linux | Should -Be 'synthetic'
        }

        It 'Refuses another source for a synthetic target' {
            { Select-CaptureBackend -Target $synthetic -Requested gdigrab -Platform Windows } | Should -Throw '*synthetic*'
        }

        It 'Refuses the synthetic source for a real target' {
            { Select-CaptureBackend -Target $monitor -Requested synthetic -Platform Windows } | Should -Throw '*synthetic*'
        }
    }

    Context 'Asking for a particular source' {
        It 'Uses the source asked for when it works' {
            Select-CaptureBackend -Target $monitor -AvailableSources $windowsSources -Requested gdigrab -MonitorCount 3 -Platform Windows | Should -Be 'gdigrab'
        }

        It 'Allows ddagrab with several monitors when asked for directly' {
            Select-CaptureBackend -Target $monitor -AvailableSources $windowsSources -Requested ddagrab -MonitorCount 3 -Platform Windows | Should -Be 'ddagrab'
        }

        It 'Throws for another platform''s source' {
            { Select-CaptureBackend -Target $monitor -AvailableSources 'x11grab' -Requested x11grab -Platform Windows } | Should -Throw '*not a Windows capture source*'
        }

        It 'Throws when the build lacks the source' {
            { Select-CaptureBackend -Target $monitor -AvailableSources 'gdigrab' -Requested gfxcapture -Platform Windows } | Should -Throw '*does not have gfxcapture*'
        }

        It 'Throws for ddagrab and a window' {
            { Select-CaptureBackend -Target $window -AvailableSources $windowsSources -Requested ddagrab -Platform Windows } | Should -Throw '*not windows*'
        }

        It 'Throws for <Requested> and a region spanning monitors' -ForEach @(
            @{ Requested = 'gfxcapture' }
            @{ Requested = 'ddagrab' }
        ) {
            { Select-CaptureBackend -Target $regionAcrossMonitors -AvailableSources $windowsSources -Requested $Requested -Platform Windows } | Should -Throw '*more than one monitor*'
        }
    }
}
