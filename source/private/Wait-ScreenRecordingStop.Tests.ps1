[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'Test-StopKeyPressed.ps1'
        'Get-ForegroundWindowHandle.ps1'
        'Update-ScreenRecordingState.ps1'
        'Read-FFmpegProgress.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Wait-ScreenRecordingStop'
    . $fileName

    $terminal = 100
    $otherWindow = 200
    #A process stand-in whose HasExited turns true after a set number of checks
    function New-TestRecording
    {
        param([int]$ExitAfterChecks = [int]::MaxValue)
        $process = [PSCustomObject]@{ Checks = 0; ExitAfter = $ExitAfterChecks }
        $process | Add-Member -MemberType ScriptProperty -Name HasExited -Value { $this.Checks++; $this.Checks -gt $this.ExitAfter }
        [PSCustomObject]@{
            Path = 'demo.mp4'
            Duration = [timespan]::FromSeconds(5)
            Elapsed = [timespan]::FromSeconds(2)
            Frames = 60
            DroppedFrames = 2
            Handle = [PSCustomObject]@{ Process = $process }
        }
    }
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Wait-ScreenRecordingStop' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock Write-Progress {}
        Mock Update-ScreenRecordingState { $Recording }
        Mock Test-StopKeyPressed { $false }
        $script:focusSequence = @($terminal)
        $script:focusIndex = 0
        Mock Get-ForegroundWindowHandle {
            $value = $script:focusSequence[[math]::Min($script:focusIndex, $script:focusSequence.Count - 1)]
            $script:focusIndex++
            $value
        }
    }

    It 'Returns Exited when ffmpeg exits, as when a duration runs out' {
        Wait-ScreenRecordingStop -Recording (New-TestRecording -ExitAfterChecks 3) -Mode Exit | Should -Be 'Exited'
    }

    It 'Returns Key when Q, Enter or Escape is pressed' {
        $script:keyChecks = 0
        Mock Test-StopKeyPressed { $script:keyChecks++; $script:keyChecks -ge 3 }
        Wait-ScreenRecordingStop -Recording (New-TestRecording) -Mode Key | Should -Be 'Key'
    }

    It 'Returns Exited in Key mode if ffmpeg exits first' {
        Wait-ScreenRecordingStop -Recording (New-TestRecording -ExitAfterChecks 2) -Mode Key | Should -Be 'Exited'
    }

    It 'Returns Focus once focus has left the terminal and come back' {
        $script:focusSequence = @($terminal, $otherWindow, $otherWindow, $terminal)
        Wait-ScreenRecordingStop -Recording (New-TestRecording) -Mode FocusReturn -WindowHandle $terminal | Should -Be 'Focus'
    }

    It 'Shows elapsed time, frames and dropped frames while waiting, then clears it' {
        $null = Wait-ScreenRecordingStop -Recording (New-TestRecording -ExitAfterChecks 2) -Mode Exit
        Should -Invoke Write-Progress -ParameterFilter { $Status -like '*00:00:02, 60 frames, 2 dropped' }
        Should -Invoke Write-Progress -ParameterFilter { $Completed }
    }
}
