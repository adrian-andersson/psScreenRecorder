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
        'Invoke-FFmpeg.ps1'
        'Get-VideoMetadata.ps1'
        'Update-ScreenRecordingState.ps1'
        'Read-FFmpegProgress.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Complete-ScreenRecording'
    . $fileName

    function New-TestRecording
    {
        param([string]$Extension = '.mp4', [string]$Codec = 'H264', [switch]$Empty, [switch]$NoFile)
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $folder
        $recordingPath = Join-Path -Path $folder -ChildPath 'demo.recording.mkv'
        if(!$NoFile)
        {
            Set-Content -LiteralPath $recordingPath -Value $(if($Empty){''}else{'pretend matroska'}) -NoNewline
        }
        $progressPath = Join-Path -Path $folder -ChildPath 'demo.progress'
        Set-Content -LiteralPath $progressPath -Value 'frame=90','out_time_us=3000000','progress=end'
        [PSCustomObject]@{
            State = 'Recording'
            Path = Join-Path -Path $folder -ChildPath "demo$Extension"
            RecordingPath = $recordingPath
            ProgressPath = $progressPath
            Codec = $Codec
            Frames = $null; DroppedFrames = $null; DuplicatedFrames = $null; Elapsed = $null; Size = $null; Speed = $null
            EndTime = $null
            Error = $null
            Handle = $null
        }
    }
    $cleanExit = [PSCustomObject]@{ ExitCode = 0; StandardError = ''; Killed = $false }
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Complete-ScreenRecording' {
    BeforeEach {
        #Remuxing writes the output file, the way ffmpeg would
        Mock Invoke-FFmpeg {
            Set-Content -LiteralPath $ArgumentList[-1] -Value 'pretend mp4'
            [PSCustomObject]@{ ExitCode = 0; StandardOutput = @(); StandardError = @() }
        }
        Mock Get-VideoMetadata { [PSCustomObject]@{ Duration = [timespan]::FromSeconds(3); Width = 1920; Height = 1080; FrameRate = 30; VideoCodec = 'h264' } }
    }

    Context 'Saving' {
        It 'Remuxes into the final container without re-encoding, then tidies up' {
            $recording = New-TestRecording
            $file = Complete-ScreenRecording -Recording $recording -ExitInfo $cleanExit
            $file.FullName | Should -Be $recording.Path
            $recording.State | Should -Be 'Saved'
            $recording.RecordingPath | Should -Not -Exist
            $recording.ProgressPath | Should -Not -Exist
            Should -Invoke Invoke-FFmpeg -ParameterFilter {
                $joined = $ArgumentList -join ' '
                $joined -like '*-map 0 -c copy -movflags +faststart*' -and $ArgumentList -notcontains '-tag:v'
            }
        }

        It 'Tags HEVC as hvc1 for Apple players' {
            $recording = New-TestRecording -Codec HEVC
            $null = Complete-ScreenRecording -Recording $recording -ExitInfo $cleanExit
            Should -Invoke Invoke-FFmpeg -ParameterFilter { ($ArgumentList -join ' ') -like '*-tag:v hvc1*' }
        }

        It 'Renames an .mkv recording into place, without running ffmpeg' {
            $recording = New-TestRecording -Extension '.mkv'
            $file = Complete-ScreenRecording -Recording $recording -ExitInfo $cleanExit
            $file.FullName | Should -Be $recording.Path
            Get-Content -LiteralPath $recording.Path | Should -Be 'pretend matroska'
            Should -Invoke Invoke-FFmpeg -Times 0 -Exactly
        }

        It 'Adds the video''s details to the file it returns' {
            $file = Complete-ScreenRecording -Recording (New-TestRecording) -ExitInfo $cleanExit
            $file.Duration | Should -Be ([timespan]::FromSeconds(3))
            $file.Width | Should -Be 1920
            $file.VideoCodec | Should -Be 'h264'
        }

        It 'Takes the final statistics from the progress file' {
            $recording = New-TestRecording
            $null = Complete-ScreenRecording -Recording $recording -ExitInfo $cleanExit
            $recording.Frames | Should -Be 90
            $recording.EndTime | Should -Not -BeNullOrEmpty
        }

        It 'Saves what there is when ffmpeg had to be killed' {
            $recording = New-TestRecording
            $null = Complete-ScreenRecording -Recording $recording -ExitInfo ([PSCustomObject]@{ ExitCode = -1; StandardError = ''; Killed = $true })
            $recording.State | Should -Be 'Saved'
        }

        It 'Still returns the file when its details can''t be read' {
            Mock Get-VideoMetadata { throw 'no ffprobe' }
            (Complete-ScreenRecording -Recording (New-TestRecording) -ExitInfo $cleanExit).Name | Should -Be 'demo.mp4'
        }
    }

    Context 'Failures' {
        It 'Fails, keeping what was recorded, when ffmpeg exited with an error' {
            $recording = New-TestRecording
            $exitInfo = [PSCustomObject]@{ ExitCode = 1; StandardError = "first line`nCould not find window"; Killed = $false }
            Complete-ScreenRecording -Recording $recording -ExitInfo $exitInfo -ErrorAction SilentlyContinue -ErrorVariable problems
            $recording.State | Should -Be 'Failed'
            $recording.Error | Should -BeLike '*code 1*Could not find window*What was recorded is in*'
            $recording.RecordingPath | Should -Exist
            $problems.Count | Should -Be 1
        }

        It 'Fails, and tidies up, when nothing was recorded' {
            $recording = New-TestRecording -Empty
            Complete-ScreenRecording -Recording $recording -ExitInfo $cleanExit -ErrorAction SilentlyContinue
            $recording.State | Should -Be 'Failed'
            $recording.Error | Should -BeLike 'Nothing was recorded*'
            $recording.RecordingPath | Should -Not -Exist
        }

        It 'Fails when there is no recording file at all' {
            $recording = New-TestRecording -NoFile
            Complete-ScreenRecording -Recording $recording -ExitInfo $cleanExit -ErrorAction SilentlyContinue
            $recording.State | Should -Be 'Failed'
        }

        It 'Keeps the .mkv, and says where, when the remux fails' {
            Mock Invoke-FFmpeg { throw 'ffmpeg exited with code 1: muxer error' }
            $recording = New-TestRecording
            Complete-ScreenRecording -Recording $recording -ExitInfo $cleanExit -ErrorAction SilentlyContinue -ErrorVariable problems
            $recording.State | Should -Be 'Failed'
            $recording.RecordingPath | Should -Exist
            $problems.Where{ $_.ToString() -like '*kept in*demo.recording.mkv*' }.Count | Should -Be 1
        }
    }
}
