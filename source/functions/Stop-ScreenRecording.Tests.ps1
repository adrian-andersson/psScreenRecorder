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
        'ToTimeSpanAttribute.ps1'
        'Stop-FFmpegProcess.ps1'
        'Complete-ScreenRecording.ps1'
        'Update-ScreenRecordingState.ps1'
        'Read-FFmpegProgress.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Stop-ScreenRecording'
    . $fileName
    . $fileName.Replace('Stop-ScreenRecording','Get-ScreenRecording')

    function New-TestRecording
    {
        param([int]$Id, [string]$State = 'Recording', [string]$Path = 'unused.mp4')
        $recording = [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.Recording'
            Id = $Id; State = $State; Path = $Path; ProgressPath = 'unused'; Error = $null
            Frames = $null; DroppedFrames = $null; DuplicatedFrames = $null; Elapsed = $null; Size = $null; Speed = $null
            Handle = [PSCustomObject]@{ Process = [PSCustomObject]@{ HasExited = $false } }
        }
        $script:psScreenRecorderRecordings.Add($recording)
        $recording
    }
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Stop-ScreenRecording' {
    BeforeEach {
        $script:psScreenRecorderRecordings = [System.Collections.Generic.List[object]]::new()
        Mock Stop-FFmpegProcess { [PSCustomObject]@{ ExitCode = 0; StandardError = ''; Killed = $false } }
        Mock Complete-ScreenRecording { $Recording.State = 'Saved'; [System.IO.FileInfo]::new("recording-$($Recording.Id).mp4") }
    }

    It 'Stops every running or ended recording when given nothing' {
        $null = New-TestRecording -Id 1
        $null = New-TestRecording -Id 2 -State 'Ended'
        $null = New-TestRecording -Id 3 -State 'Failed'
        $saved = @(Stop-ScreenRecording)
        $saved.Name | Should -Be @('recording-1.mp4','recording-2.mp4')
        Should -Invoke Stop-FFmpegProcess -Times 2 -Exactly
    }

    It 'Warns when there is nothing to stop' {
        Mock Write-Warning {}
        Stop-ScreenRecording | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*no recordings*' }
    }

    It 'Stops only the recording given, from the pipeline' {
        $null = New-TestRecording -Id 1
        $second = New-TestRecording -Id 2
        ($second | Stop-ScreenRecording).Name | Should -Be 'recording-2.mp4'
        Should -Invoke Stop-FFmpegProcess -Times 1 -Exactly
    }

    It 'Stops by Id, and writes an error for one that does not exist' {
        $null = New-TestRecording -Id 1
        (Stop-ScreenRecording -Id 1,9 -ErrorVariable problems -ErrorAction SilentlyContinue).Name | Should -Be 'recording-1.mp4'
        $problems[0].ToString() | Should -BeLike '*no recording with Id 9*'
    }

    It 'Returns the file again for a recording already saved, without stopping anything' {
        $savedFile = Join-Path -Path $TestDrive -ChildPath 'done.mp4'
        Set-Content -LiteralPath $savedFile -Value 'video'
        $recording = New-TestRecording -Id 1 -State 'Saved' -Path $savedFile
        ($recording | Stop-ScreenRecording).FullName | Should -Be $savedFile
        Should -Invoke Stop-FFmpegProcess -Times 0 -Exactly
    }

    It 'Writes the error for a recording that failed' {
        $recording = New-TestRecording -Id 1 -State 'Failed'
        $recording.Error = 'capture device lost'
        $recording | Stop-ScreenRecording -ErrorVariable problems -ErrorAction SilentlyContinue
        $problems[0].ToString() | Should -BeLike '*capture device lost*'
    }

    It 'Passes -Timeout to the stop' {
        $recording = New-TestRecording -Id 1
        $null = $recording | Stop-ScreenRecording -Timeout 45
        Should -Invoke Stop-FFmpegProcess -ParameterFilter { $Timeout -eq [timespan]::FromSeconds(45) }
    }

    It 'Does nothing with -WhatIf' {
        $recording = New-TestRecording -Id 1
        $recording | Stop-ScreenRecording -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Stop-FFmpegProcess -Times 0 -Exactly
    }
}

Describe 'Get-ScreenRecording' {
    BeforeEach {
        $script:psScreenRecorderRecordings = [System.Collections.Generic.List[object]]::new()
        Mock Update-ScreenRecordingState { $Recording }
    }

    It 'Returns nothing before anything has been recorded' {
        $script:psScreenRecorderRecordings = $null
        Get-ScreenRecording | Should -BeNullOrEmpty
    }

    It 'Lists every recording, refreshing only the ones still running' {
        $null = New-TestRecording -Id 1
        $null = New-TestRecording -Id 2 -State 'Saved'
        @(Get-ScreenRecording).Id | Should -Be @(1,2)
        Should -Invoke Update-ScreenRecordingState -Times 1 -Exactly
    }

    It 'Filters by Id and by State' {
        $null = New-TestRecording -Id 1
        $null = New-TestRecording -Id 2 -State 'Saved'
        $null = New-TestRecording -Id 3 -State 'Failed'
        (Get-ScreenRecording -Id 3).State | Should -Be 'Failed'
        @(Get-ScreenRecording -State Recording,Saved).Id | Should -Be @(1,2)
    }
}
