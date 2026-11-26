[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#Unit tests: ffmpeg, the capture targets and the process are mocked. tests/Recording.Integration.Tests.ps1 records for real
BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'ToTimeSpanAttribute.ps1'
        'New-CaptureTarget.ps1'
        'Get-CaptureTarget.ps1'
        'Find-FFmpeg.ps1'
        'Select-CaptureBackend.ps1'
        'Select-VideoEncoder.ps1'
        'Get-CaptureInputArgument.ps1'
        'Get-DefaultRecordingPath.ps1'
        'Start-FFmpegProcess.ps1'
        'Stop-FFmpegProcess.ps1'
        'Read-FFmpegProgress.ps1'
        'Complete-ScreenRecording.ps1'
        'Register-ScreenRecorderExitHandler.ps1'
        'Get-TerminalWindowHandle.ps1'
        'Wait-WindowFocus.ps1'
        'Wait-ScreenRecordingStop.ps1'
        'Stop-ScreenRecording.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Start-ScreenRecording'
    . $fileName

    $outputFolder = Join-Path -Path $TestDrive -ChildPath 'recordings'
    $null = New-Item -ItemType Directory -Path $outputFolder -Force
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Start-ScreenRecording' {
    BeforeEach {
        $script:psScreenRecorderRecordings = [System.Collections.Generic.List[object]]::new()
        $script:psScreenRecorderNextId = 1
        $primary = New-CaptureTarget -Kind Monitor -Index 0 -Name 'Primary' -X 0 -Y 0 -Width 1920 -Height 1080 -IsPrimary $true -Handle 1001
        $secondary = New-CaptureTarget -Kind Monitor -Index 1 -Name 'Second' -X 1920 -Y 0 -Width 1280 -Height 1024 -Handle 1002
        Mock Get-CaptureTarget -ParameterFilter { $PSCmdlet.ParameterSetName -eq 'Monitor' } { $secondary; $primary }
        Mock Find-FFmpeg {
            [PSCustomObject]@{ FFmpegPath = 'ffmpeg'; CaptureSources = @('gfxcapture','ddagrab','gdigrab','avfoundation','x11grab'); Encoders = @('libx264','libx264rgb','libx265','h264_nvenc') }
        }
        Mock Start-FFmpegProcess {
            [PSCustomObject]@{ Process = [PSCustomObject]@{ HasExited = $false; ExitCode = 0 }; ProcessId = 4321; StartTime = [datetime]::Now }
        }
        #A first progress block, so the start-up check moves straight on
        Mock Read-FFmpegProgress { [PSCustomObject]@{ Frame = 1 } }
        Mock Register-ScreenRecorderExitHandler {}
    }

    Context 'What to record' {
        It 'Records the primary monitor by default' {
            $recording = Start-ScreenRecording -Path $outputFolder
            $recording.TargetName | Should -Be 'Primary'
            $recording.State | Should -Be 'Recording'
            $recording.PSTypeNames | Should -Contain 'psScreenRecorder.Recording'
        }

        It 'Records the monitor asked for by index' {
            (Start-ScreenRecording -Monitor 1 -Path $outputFolder).TargetName | Should -Be 'Second'
        }

        It 'Throws, listing the monitors, for an index that does not exist' {
            { Start-ScreenRecording -Monitor 5 -Path $outputFolder } | Should -Throw '*no monitor 5*0 (Primary)*'
        }

        It 'Records a target from the pipeline' {
            ($secondary | Start-ScreenRecording -Path $outputFolder).Target.Handle | Should -Be 1002
        }

        It 'Records a region, rounding its size down to even numbers, inside the monitor it fits' {
            $recording = Start-ScreenRecording -Rectangle 1930,10,801,451 -Path $outputFolder
            $recording.Target.Kind | Should -Be 'Region'
            $recording.Target.Width | Should -Be 800
            $recording.Target.Height | Should -Be 450
            $recording.Target.Monitor.Name | Should -Be 'Second'
        }

        It 'Records a region spanning monitors with gdigrab' -Skip:(!$IsWindows) {
            (Start-ScreenRecording -Rectangle 1800,10,400,300 -Path $outputFolder).Backend | Should -Be 'gdigrab'
        }

        It 'Throws for a region smaller than 2 pixels' {
            { Start-ScreenRecording -Rectangle 0,0,1,100 -Path $outputFolder } | Should -Throw '*at least 2 pixels*'
        }

        It 'Matches a window anywhere in its title when no wildcard is given' {
            Mock Get-CaptureTarget -ParameterFilter { $Window } { New-CaptureTarget -Kind Window -Name 'Notes - Notepad' -Title 'Notes - Notepad' -X 0 -Y 0 -Width 640 -Height 480 -Handle 77 }
            $null = Start-ScreenRecording -Window 'Notepad' -Path $outputFolder
            Should -Invoke Get-CaptureTarget -ParameterFilter { $Window -and $Name -eq '*Notepad*' }
        }

        It 'Throws, listing them, when several windows match' {
            Mock Get-CaptureTarget -ParameterFilter { $Window } {
                New-CaptureTarget -Kind Window -Title 'One' -ProcessName 'app'
                New-CaptureTarget -Kind Window -Title 'Two' -ProcessName 'app'
            }
            { Start-ScreenRecording -Window 'app' -Path $outputFolder } | Should -Throw "*2 windows match*'One' (app)*"
        }

        It 'Throws when no window matches' {
            Mock Get-CaptureTarget -ParameterFilter { $Window } {}
            { Start-ScreenRecording -Window 'nothing' -Path $outputFolder } | Should -Throw '*No window matches*'
        }

        It 'Throws for a minimized window' {
            $minimized = New-CaptureTarget -Kind Window -Name 'Mail' -IsMinimized $true
            { $minimized | Start-ScreenRecording -Path $outputFolder } | Should -Throw '*minimized*'
        }

        It 'Records a test pattern with -Synthetic, without looking for monitors' {
            $recording = Start-ScreenRecording -Synthetic -Path $outputFolder
            $recording.Backend | Should -Be 'synthetic'
            Should -Invoke Get-CaptureTarget -Times 0 -Exactly
        }
    }

    Context 'The ffmpeg command' {
        It 'Records into Matroska next to the final file, with progress to a temporary file' {
            $recording = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'demo.mp4')
            $recording.RecordingPath | Should -Be (Join-Path -Path $outputFolder -ChildPath 'demo.recording.mkv')
            $recording.Arguments[-1] | Should -Be $recording.RecordingPath
            $recording.Arguments[-2] | Should -Be 'matroska'
            ($recording.Arguments -join ' ') | Should -BeLike "*-progress file:$($recording.ProgressPath) -stats_period 0.5*"
        }

        It 'Builds the filter chain: capture filters, frame rate, even size, then the encoder''s pixel format' {
            $recording = Start-ScreenRecording -Synthetic -Path $outputFolder -Fps 24
            $filter = $recording.Arguments[[array]::IndexOf($recording.Arguments,'-vf') + 1]
            $filter | Should -Be 'fps=24,crop=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p'
        }

        It 'Uses the encoder chosen for the codec and quality' {
            $recording = Start-ScreenRecording -Synthetic -Path $outputFolder -Codec HEVC
            $recording.Encoder | Should -Be 'libx265'
            ($recording.Arguments -join ' ') | Should -BeLike '*-c:v libx265 -preset superfast*'
        }

        It 'Stops ffmpeg itself after -Duration, written with a dot whatever the culture' {
            $savedCulture = [cultureinfo]::CurrentCulture
            try{
                [cultureinfo]::CurrentCulture = [cultureinfo]::GetCultureInfo('de-DE')
                $recording = Start-ScreenRecording -Synthetic -Path $outputFolder -Duration 2.5
                $recording.Arguments[[array]::IndexOf($recording.Arguments,'-t') + 1] | Should -Be '2.5'
            }finally{
                [cultureinfo]::CurrentCulture = $savedCulture
            }
        }

        It 'Adds -FFmpegInputArgument before the capture input, and -FFmpegOutputArgument before the output' {
            $recording = Start-ScreenRecording -Synthetic -Path $outputFolder -FFmpegInputArgument '-thread_queue_size','512' -FFmpegOutputArgument '-metadata','title=demo'
            $arguments = [System.Collections.Generic.List[string]]$recording.Arguments
            $arguments.IndexOf('-thread_queue_size') | Should -BeLessThan $arguments.IndexOf('lavfi')
            $arguments.IndexOf('title=demo') | Should -BeLessThan $arguments.IndexOf('matroska')
        }

        It 'Uses -VideoEncoder by name, with no settings' {
            $recording = Start-ScreenRecording -Synthetic -Path $outputFolder -VideoEncoder 'libvvenc'
            ($recording.Arguments -join ' ') | Should -BeLike '*-c:v libvvenc -f matroska*'
        }

        It 'Leaves the cursor out with -HideCursor' -Skip:(!$IsWindows) {
            $recording = Start-ScreenRecording -Path $outputFolder -HideCursor
            ($recording.Arguments -join ' ') | Should -BeLike '*capture_cursor=0*'
        }
    }

    Context 'Where it saves' {
        It 'Names the file after the time in the folder given' {
            (Start-ScreenRecording -Synthetic -Path $outputFolder).Path | Should -BeLike (Join-Path -Path $outputFolder -ChildPath 'Screen Recording *.mp4')
        }

        It 'Saves Lossless as .mkv by default, as most players can''t play RGB video' {
            (Start-ScreenRecording -Synthetic -Path $outputFolder -Quality Lossless).Path | Should -BeLike '*.mkv'
        }

        It 'Warns about players when Lossless goes into .mp4' {
            Mock Write-Warning {}
            $null = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'lossless.mp4') -Quality Lossless
            Should -Invoke Write-Warning -ParameterFilter { $Message -like '*Lossless*' }
        }

        It 'Throws for a container it can''t save' {
            { Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'demo.avi') } | Should -Throw "*not '.avi'*"
        }

        It 'Throws when the file exists, unless -Force' {
            $existing = Join-Path -Path $outputFolder -ChildPath 'exists.mp4'
            Set-Content -LiteralPath $existing -Value 'old'
            { Start-ScreenRecording -Synthetic -Path $existing } | Should -Throw '*already exists*'
            { Start-ScreenRecording -Synthetic -Path $existing -Force } | Should -Not -Throw
        }

        It 'Throws when the folder does not exist' {
            { Start-ScreenRecording -Synthetic -Path (Join-Path -Path $TestDrive -ChildPath 'nowhere/demo.mp4') } | Should -Throw '*does not exist*'
        }
    }

    Context 'Starting and failing' {
        It 'Adds the recording to the session list, numbering each one' {
            $first = Start-ScreenRecording -Synthetic -Path $outputFolder
            $second = Start-ScreenRecording -Synthetic -Path (Join-Path -Path $outputFolder -ChildPath 'second.mp4')
            $first.Id | Should -Be 1
            $second.Id | Should -Be 2
            $script:psScreenRecorderRecordings.Count | Should -Be 2
            Should -Invoke Register-ScreenRecorderExitHandler -Times 2
        }

        It 'Throws with ffmpeg''s error when the recording can''t start' {
            Mock Start-FFmpegProcess { [PSCustomObject]@{ Process = [PSCustomObject]@{ HasExited = $true; ExitCode = 1 }; ProcessId = 1; StartTime = [datetime]::Now } }
            Mock Stop-FFmpegProcess { [PSCustomObject]@{ ExitCode = 1; StandardError = 'Failed to capture window'; Killed = $false } }
            { Start-ScreenRecording -Synthetic -Path $outputFolder } | Should -Throw '*could not start*Failed to capture window*'
        }

        It 'Does not start ffmpeg with -WhatIf' {
            $null = Start-ScreenRecording -Synthetic -Path $outputFolder -WhatIf
            Should -Invoke Start-FFmpegProcess -Times 0 -Exactly
        }

        It 'Counts down -Delay before starting' {
            Mock Start-Sleep {}
            Mock Write-Progress {}
            $null = Start-ScreenRecording -Synthetic -Path $outputFolder -Delay 0.3
            Should -Invoke Write-Progress -ParameterFilter { $Activity -eq 'Recording starts in' -and !$Completed }
        }

        It 'Throws for <Case>' -ForEach @(
            @{ Case = 'a zero duration'; Splat = @{ Duration = 0 }; Message = '*more than zero*' }
            @{ Case = 'a negative delay'; Splat = @{ Delay = -1 }; Message = '*cannot be negative*' }
        ) {
            { Start-ScreenRecording -Synthetic -Path $outputFolder @Splat } | Should -Throw $Message
        }
    }

    Context 'Waiting' {
        BeforeEach {
            Mock Wait-ScreenRecordingStop { 'Exited' }
            Mock Stop-ScreenRecording { [System.IO.FileInfo]::new('saved.mp4') }
        }

        It 'Waits for the duration, then stops and returns the file, with -Wait -Duration' {
            $result = Start-ScreenRecording -Synthetic -Path $outputFolder -Duration 5 -Wait
            $result.Name | Should -Be 'saved.mp4'
            Should -Invoke Wait-ScreenRecordingStop -ParameterFilter { $Mode -eq 'Exit' }
            Should -Invoke Stop-ScreenRecording -Times 1 -Exactly
        }

        It 'Still stops the recording if the wait is interrupted, as by Ctrl+C' {
            Mock Wait-ScreenRecordingStop { throw 'interrupted' }
            { Start-ScreenRecording -Synthetic -Path $outputFolder -Duration 5 -Wait } | Should -Throw 'interrupted'
            Should -Invoke Stop-ScreenRecording -Times 1 -Exactly
        }

        It 'Needs -Duration when there''s no console to press a key in' -Skip:(![Console]::IsInputRedirected) {
            { Start-ScreenRecording -Synthetic -Path $outputFolder -Wait } | Should -Throw '*needs -Duration*'
        }

        It 'Refuses the focus modes outside Windows' -Skip:$IsWindows {
            { Start-ScreenRecording -Synthetic -Path $outputFolder -StartOnFocusLoss } | Should -Throw '*only supported on Windows*'
        }

        It 'Waits for focus to leave the terminal, then records until it returns' -Skip:(!$IsWindows) {
            Mock Get-TerminalWindowHandle { 500 }
            Mock Wait-WindowFocus { $true }
            Mock Start-Sleep {}
            Mock Write-Progress {}
            Mock Write-Host {}
            $null = Start-ScreenRecording -Synthetic -Path $outputFolder -StartOnFocusLoss -StopOnFocusReturn
            Should -Invoke Wait-WindowFocus -ParameterFilter { $WindowHandle -eq 500 -and $Until -eq 'Lost' }
            Should -Invoke Wait-ScreenRecordingStop -ParameterFilter { $Mode -eq 'FocusReturn' -and $WindowHandle -eq 500 }
            #Two seconds' delay after focus leaves, unless -Delay says otherwise
            Should -Invoke Write-Progress -ParameterFilter { $Activity -eq 'Recording starts in' -and !$Completed }
        }
    }
}
