<#
    Recording, end to end, with a real ffmpeg.

    The synthetic source (ffmpeg's testsrc2 test pattern, paced in real time) runs the whole recording
    lifecycle with no screen, so these run on every CI runner: start, check progress, stop, save, and
    survive ffmpeg being killed.

    'Real screen capture' records the actual desktop. It runs on Windows when not in CI, or anywhere when
    PSSCREENRECORDER_TEST_CAPTURE is 1. CI runners may have no usable desktop, so it's opt-in there.
    Recordings go in TestDrive, which Pester deletes afterwards.

    Skipped entirely if ffmpeg can't be found.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeDiscovery {
    $ffmpegAvailable = [bool]([Environment]::GetEnvironmentVariable('PSSCREENRECORDER_FFMPEG') -or (Get-Command -Name 'ffmpeg' -CommandType Application -ErrorAction Ignore))
    $captureWanted = [Environment]::GetEnvironmentVariable('PSSCREENRECORDER_TEST_CAPTURE') -eq '1' -or ($IsWindows -and [Environment]::GetEnvironmentVariable('CI') -ne 'true')
    $canCapture = $ffmpegAvailable -and $captureWanted
}

BeforeAll {
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $sourcePath = Join-Path -Path $projectRoot -ChildPath 'source'
    foreach($folder in 'enums','classes','validationClasses','private','functions')
    {
        $folderPath = Join-Path -Path $sourcePath -ChildPath $folder
        if(Test-Path -LiteralPath $folderPath)
        {
            Get-ChildItem -LiteralPath $folderPath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object { . $_.FullName }
        }
    }
    $savedCache = $env:PSSCREENRECORDER_CACHE
    $env:PSSCREENRECORDER_CACHE = Join-Path -Path $TestDrive -ChildPath 'cache'
    $script:psScreenRecorderRecordings = [System.Collections.Generic.List[object]]::new()
    $outputFolder = Join-Path -Path $TestDrive -ChildPath 'recordings with spaces'
    $null = New-Item -ItemType Directory -Path $outputFolder -Force
}

AfterAll {
    #Nothing should be left running, but make sure
    foreach($recording in @($script:psScreenRecorderRecordings))
    {
        if($recording.Handle -and !$recording.Handle.Process.HasExited)
        {
            $recording.Handle.Process.Kill($true)
        }
    }
    $env:PSSCREENRECORDER_CACHE = $savedCache
}

Describe 'Recording with a real ffmpeg' -Skip:(!$ffmpegAvailable) {
    Context 'The recording lifecycle, on the synthetic source' {
        It 'Starts, reports progress, stops and saves a playable MP4' {
            $path = Join-Path -Path $outputFolder -ChildPath 'lifecycle.mp4'
            $recording = Start-ScreenRecording -Synthetic -Path $path
            $recording.State | Should -Be 'Recording'
            Start-Sleep -Seconds 2

            $running = Get-ScreenRecording -Id $recording.Id
            $running.Frames | Should -BeGreaterThan 0
            $running.Elapsed.TotalSeconds | Should -BeGreaterThan 0.5

            $file = $recording | Stop-ScreenRecording
            $file.FullName | Should -Be $path
            $recording.State | Should -Be 'Saved'
            $recording.RecordingPath | Should -Not -Exist
            $recording.ProgressPath | Should -Not -Exist

            $metadata = Get-VideoMetadata -Path $path
            $metadata.Width | Should -Be 640
            $metadata.Height | Should -Be 360
            $metadata.VideoCodec | Should -Be 'h264'
            $metadata.Duration.TotalSeconds | Should -BeGreaterThan 1.5
            $metadata.Container | Should -BeLike '*mp4*'
        }

        It 'Records for -Duration and returns the file with -Wait' {
            $file = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'duration.mp4') -Duration 1.5 -Wait
            $file.Duration.TotalSeconds | Should -BeGreaterOrEqual 1.4
            $file.Duration.TotalSeconds | Should -BeLessOrEqual 1.7
        }

        It 'Saves a recording that ended by itself, once stopped' {
            $recording = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'ended.mp4') -Duration 1
            $null = $recording.Handle.Process.WaitForExit(30000)
            (Get-ScreenRecording -Id $recording.Id).State | Should -Be 'Ended'
            (Stop-ScreenRecording -Id $recording.Id).Name | Should -Be 'ended.mp4'
        }

        It 'Saves as <Extension>' -ForEach @(
            @{ Extension = '.mkv'; Container = '*matroska*' }
            @{ Extension = '.mov'; Container = '*mov*' }
        ) {
            $file = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath "container$Extension") -Duration 1 -Wait
            (Get-VideoMetadata -Path $file.FullName).Container | Should -BeLike $Container
        }

        It 'Records HEVC with x265, and tags it for Apple players' {
            $file = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'hevc.mp4') -Codec HEVC -Encoder Software -Duration 1 -Wait
            $metadata = Get-VideoMetadata -Path $file.FullName
            $metadata.VideoCodec | Should -Be 'hevc'
            $metadata.Streams[0].codec_tag_string | Should -Be 'hvc1'
        }

        It 'Records losslessly in RGB' {
            $file = Start-ScreenRecording -Synthetic -Path $outputFolder -Quality Lossless -Duration 1 -Wait
            $file.Extension | Should -Be '.mkv'
            (Get-VideoMetadata -Path $file.FullName).PixelFormat | Should -Be 'gbrp'
        }

        It 'Keeps a recording readable when ffmpeg is killed part way through' {
            $recording = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'killed.mp4')
            #Wait for a couple of seconds of video, however slow the runner is, so at least one cluster is on disk
            $deadline = [datetime]::Now.AddSeconds(20)
            while((Get-ScreenRecording -Id $recording.Id).Frames -lt 75 -and [datetime]::Now -lt $deadline)
            {
                Start-Sleep -Milliseconds 250
            }
            $recording.Handle.Process.Kill($true)
            $null = $recording.Handle.Process.WaitForExit(30000)
            $file = Stop-ScreenRecording -Id $recording.Id -WarningAction SilentlyContinue
            #What was recorded is saved, with its index rebuilt, rather than lost
            $recording.State | Should -Be 'Saved'
            $recording.RecordingPath | Should -Not -Exist
            (Get-VideoMetadata -Path $file.FullName -CountFrames).FrameCount | Should -BeGreaterThan 10
        }

        It 'Repairs a recording left behind by a killed ffmpeg into a normal file' {
            $recording = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'to repair.mp4')
            $deadline = [datetime]::Now.AddSeconds(20)
            while((Get-ScreenRecording -Id $recording.Id).Frames -lt 60 -and [datetime]::Now -lt $deadline)
            {
                Start-Sleep -Milliseconds 250
            }
            $recording.Handle.Process.Kill($true)
            $null = $recording.Handle.Process.WaitForExit(30000)

            $repaired = Repair-ScreenRecording -Path $recording.RecordingPath
            $repaired.Name | Should -Be 'to repair.mp4'
            $repaired.Duration.TotalSeconds | Should -BeGreaterThan 1
            (Get-VideoMetadata -Path $repaired.FullName).Container | Should -BeLike '*mp4*'
            $recording.RecordingPath | Should -Not -Exist
        }

        It 'Records a script block running with Invoke-ScreenRecording, keeping its output on screen' {
            $file = Invoke-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'invoked.mp4') -LeadIn 0.2 -LeadOut 0.3 -ScriptBlock { Start-Sleep -Milliseconds 800; 'shown on screen' } 6>$null
            $file.Name | Should -Be 'invoked.mp4'
            $file.Duration.TotalSeconds | Should -BeGreaterThan 1
        }

        It 'Does not leave ffmpeg recording when the PowerShell session ends without stopping it' {
            #A child session loads the module from source, starts recording, and ends without stopping it
            $sourceFiles = foreach($folder in 'enums','classes','validationClasses','private','functions')
            {
                $folderPath = Join-Path -Path $sourcePath -ChildPath $folder
                if(Test-Path -LiteralPath $folderPath)
                {
                    Get-ChildItem -LiteralPath $folderPath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object { $_.FullName }
                }
            }
            $pidFile = Join-Path -Path $TestDrive -ChildPath 'ffmpeg.pid'
            $childRecording = Join-Path -Path $outputFolder -ChildPath 'abandoned.mp4'
            $childScript = Join-Path -Path $TestDrive -ChildPath 'abandon.ps1'
            Set-Content -LiteralPath $childScript -Value @(
                foreach($file in $sourceFiles){ ". '$($file.Replace("'","''"))'" }
                "`$recording = Start-ScreenRecording -Synthetic -Path '$($childRecording.Replace("'","''"))'"
                "Set-Content -LiteralPath '$($pidFile.Replace("'","''"))' -Value `$recording.ProcessId"
                'Start-Sleep -Seconds 2'
            )
            & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $childScript
            $ffmpegId = [int](Get-Content -LiteralPath $pidFile)

            $deadline = [datetime]::Now.AddSeconds(15)
            while((Get-Process -Id $ffmpegId -ErrorAction Ignore) -and [datetime]::Now -lt $deadline)
            {
                Start-Sleep -Milliseconds 250
            }
            Get-Process -Id $ffmpegId -ErrorAction Ignore | Should -BeNullOrEmpty
            #What was recorded is still there, and readable
            $abandoned = Join-Path -Path $outputFolder -ChildPath 'abandoned.recording.mkv'
            (Get-VideoMetadata -Path $abandoned -CountFrames).FrameCount | Should -BeGreaterThan 10

            #This session can see what the other left behind, and finish it into the file it was going to be
            $leftBehind = Get-ScreenRecording -AllSessions -State Abandoned | Where-Object Path -eq $childRecording
            $leftBehind.Session | Should -Be 'Other'
            $saved = $leftBehind | Stop-ScreenRecording
            $saved.FullName | Should -Be $childRecording
            $saved.Duration.TotalSeconds | Should -BeGreaterThan 1
            $abandoned | Should -Not -Exist
            Get-ScreenRecording -AllSessions | Where-Object Path -eq $childRecording | Should -BeNullOrEmpty
        }

        It 'Stops and saves a recording still running in another session' {
            $sourceFiles = foreach($folder in 'enums','classes','validationClasses','private','functions')
            {
                $folderPath = Join-Path -Path $sourcePath -ChildPath $folder
                if(Test-Path -LiteralPath $folderPath)
                {
                    Get-ChildItem -LiteralPath $folderPath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object { $_.FullName }
                }
            }
            $readyFile = Join-Path -Path $TestDrive -ChildPath 'other.ready'
            $otherRecording = Join-Path -Path $outputFolder -ChildPath 'other session.mp4'
            $childScript = Join-Path -Path $TestDrive -ChildPath 'keep-recording.ps1'
            #The other session records, says so, then waits, as a session someone has left recording would
            Set-Content -LiteralPath $childScript -Value @(
                foreach($file in $sourceFiles){ ". '$($file.Replace("'","''"))'" }
                "`$null = Start-ScreenRecording -Synthetic -Path '$($otherRecording.Replace("'","''"))'"
                "Set-Content -LiteralPath '$($readyFile.Replace("'","''"))' -Value ready"
                'Start-Sleep -Seconds 60'
            )
            $otherSplat = @{ FilePath = (Get-Process -Id $PID).Path; ArgumentList = '-NoProfile','-NonInteractive','-File',$childScript; PassThru = $true }
            if($IsWindows){ $otherSplat.WindowStyle = 'Hidden' }
            $otherSession = Start-Process @otherSplat
            try{
                $deadline = [datetime]::Now.AddSeconds(30)
                while(!(Test-Path -LiteralPath $readyFile) -and [datetime]::Now -lt $deadline){ Start-Sleep -Milliseconds 250 }
                Start-Sleep -Seconds 2

                $running = Get-ScreenRecording -AllSessions -State Recording | Where-Object Path -eq $otherRecording
                $running.Session | Should -Be 'Other'
                $saved = $running | Stop-ScreenRecording
                $saved.FullName | Should -Be $otherRecording
                (Get-VideoMetadata -Path $saved.FullName -CountFrames).FrameCount | Should -BeGreaterThan 10
            }finally{
                if(!$otherSession.HasExited){ $otherSession.Kill($true) }
            }
        }

        It 'Pipes straight into ConvertTo-Gif' {
            $gif = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'to gif.mp4') -Duration 1 -Wait | ConvertTo-Gif -Width 320
            $gif.Extension | Should -Be '.gif'
            (Get-VideoMetadata -Path $gif.FullName).Width | Should -Be 320
        }
    }

    Context 'Real screen capture' -Skip:(!$canCapture) {
        It 'Records the primary monitor at its full physical size' {
            $primary = Get-CaptureTarget | Where-Object IsPrimary | Select-Object -First 1
            $file = Start-ScreenRecording -Path (Join-Path -Path $outputFolder -ChildPath 'monitor.mp4') -Duration 1 -Wait
            $file.Width | Should -Be ($primary.Width - ($primary.Width % 2))
            $file.Height | Should -Be ($primary.Height - ($primary.Height % 2))
        }

        It 'Records a region at exactly the size asked for' {
            $file = Start-ScreenRecording -Rectangle 0,0,640,360 -Path (Join-Path -Path $outputFolder -ChildPath 'region.mp4') -Duration 1 -Wait
            $file.Width | Should -Be 640
            $file.Height | Should -Be 360
        }

        It 'Records the region with <Backend>' -Skip:(!$IsWindows) -ForEach @(
            @{ Backend = 'gfxcapture' }
            @{ Backend = 'ddagrab' }
            @{ Backend = 'gdigrab' }
        ) {
            if($Backend -notin (Find-FFmpeg -IncludeCapability).CaptureSources)
            {
                Set-ItResult -Skipped -Because "this ffmpeg build has no $Backend"
                return
            }
            $file = Start-ScreenRecording -Rectangle 0,0,320,240 -Backend $Backend -Path (Join-Path -Path $outputFolder -ChildPath "region-$Backend.mp4") -Duration 1 -Wait
            $file.Width | Should -Be 320
        }

        It 'Records the current terminal''s window' -Skip:(!$IsWindows) {
            $file = Start-ScreenRecording -CurrentTerminal -Path (Join-Path -Path $outputFolder -ChildPath 'terminal.mp4') -Duration 1 -Wait -WarningAction SilentlyContinue
            $file.Width | Should -BeGreaterThan 100
        }
    }
}
