[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#Write-RecordingInfoFile, Get-OtherSessionRecording and Stop-OtherSessionRecording, which work together.
#Recording in one session and finishing it from another runs for real in tests/Recording.Integration.Tests.ps1
BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'Get-ScreenRecorderCacheFolder.ps1'
        'Read-FFmpegProgress.ps1'
        'Write-RecordingInfoFile.ps1'
        'Stop-OtherSessionRecording.ps1'
        'Repair-ScreenRecording.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-OtherSessionRecording'
    . $fileName

    #Writes an info file as another session would have
    function New-OtherInfoFile
    {
        param([int]$ProcessId, [string]$ProcessStartTimeUtc, [int]$OwnerProcessId = 999999, [switch]$NoRecordingFile, [switch]$EmptyRecordingFile)
        $folder = Join-Path -Path $env:PSSCREENRECORDER_CACHE -ChildPath 'recordings'
        $null = New-Item -ItemType Directory -Path $folder -Force
        $name = [guid]::NewGuid().ToString('N')
        $recordingPath = Join-Path -Path $TestDrive -ChildPath "$name.recording.mkv"
        if(!$NoRecordingFile)
        {
            Set-Content -LiteralPath $recordingPath -Value $(if($EmptyRecordingFile){''}else{'pretend matroska'}) -NoNewline
        }
        $info = [ordered]@{
            ProcessId = $ProcessId
            ProcessStartTimeUtc = $ProcessStartTimeUtc
            OwnerProcessId = $OwnerProcessId
            TargetName = 'Primary'
            Path = Join-Path -Path $TestDrive -ChildPath "$name.mp4"
            RecordingPath = $recordingPath
            ProgressPath = Join-Path -Path $TestDrive -ChildPath "$name.progress"
            Codec = 'H264'
            StartTimeUtc = [datetime]::UtcNow.ToString('o')
        }
        $infoPath = Join-Path -Path $folder -ChildPath "$name.json"
        ConvertTo-Json -InputObject $info | Set-Content -LiteralPath $infoPath
        $infoPath
    }
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Recordings from other sessions' {
    BeforeAll {
        $savedCache = $env:PSSCREENRECORDER_CACHE
    }
    AfterAll {
        $env:PSSCREENRECORDER_CACHE = $savedCache
    }
    BeforeEach {
        $env:PSSCREENRECORDER_CACHE = Join-Path -Path $TestDrive -ChildPath "cache $([guid]::NewGuid().ToString('N'))"
    }

    Context 'Write-RecordingInfoFile' {
        It 'Saves what another session needs, tagged with this session' {
            $recording = [PSCustomObject]@{
                ProcessId = $PID; TargetName = 'Primary'; Path = 'a.mp4'; RecordingPath = 'a.recording.mkv'; ProgressPath = 'a.progress'
                Codec = 'HEVC'; Backend = 'gfxcapture'; Encoder = 'hevc_nvenc'; StartTime = [datetime]::Now
                Handle = [PSCustomObject]@{ Process = Get-Process -Id $PID }
            }
            $infoPath = Write-RecordingInfoFile -Recording $recording
            $infoPath | Should -Exist
            $info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json -DateKind String
            $info.OwnerProcessId | Should -Be $PID
            $info.Codec | Should -Be 'HEVC'
            $info.ProcessStartTimeUtc | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-OtherSessionRecording' {
        It 'Finds nothing when there is no recordings folder' {
            Get-OtherSessionRecording | Should -BeNullOrEmpty
        }

        It 'Skips this session''s own recordings' {
            $null = New-OtherInfoFile -ProcessId $PID -OwnerProcessId $PID
            Get-OtherSessionRecording | Should -BeNullOrEmpty
        }

        It 'Reports a recording whose ffmpeg is still running as Recording' {
            #This test process stands in for the other session's ffmpeg
            $null = New-OtherInfoFile -ProcessId $PID -ProcessStartTimeUtc (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
            $found = Get-OtherSessionRecording
            $found.State | Should -Be 'Recording'
            $found.Session | Should -Be 'Other'
            $found.PSTypeNames | Should -Contain 'psScreenRecorder.Recording'
        }

        It 'Treats a reused process ID, with a different start time, as gone' {
            $null = New-OtherInfoFile -ProcessId $PID -ProcessStartTimeUtc ([datetime]::UtcNow.AddDays(-3).ToString('o'))
            (Get-OtherSessionRecording).State | Should -Be 'Abandoned'
        }

        It 'Reports a recording whose ffmpeg has gone as Abandoned' {
            $null = New-OtherInfoFile -ProcessId 999998
            (Get-OtherSessionRecording).State | Should -Be 'Abandoned'
        }

        It 'Deletes stale info files, whose ffmpeg has gone and recording is <Case>' -ForEach @(
            @{ Case = 'missing'; Splat = @{ NoRecordingFile = $true } }
            @{ Case = 'empty'; Splat = @{ EmptyRecordingFile = $true } }
        ) {
            $infoPath = New-OtherInfoFile -ProcessId 999998 @Splat
            Get-OtherSessionRecording | Should -BeNullOrEmpty
            $infoPath | Should -Not -Exist
        }

        It 'Skips unreadable info files' {
            $folder = Join-Path -Path $env:PSSCREENRECORDER_CACHE -ChildPath 'recordings'
            $null = New-Item -ItemType Directory -Path $folder -Force
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'bad.json') -Value '{ not json'
            Get-OtherSessionRecording | Should -BeNullOrEmpty
        }
    }

    Context 'Stop-OtherSessionRecording' {
        BeforeEach {
            Mock Repair-ScreenRecording { [System.IO.FileInfo]::new($Destination) }
        }

        It 'Repairs an abandoned recording into its final file, and removes its info file' {
            $infoPath = New-OtherInfoFile -ProcessId 999998
            $abandoned = Get-OtherSessionRecording
            $file = Stop-OtherSessionRecording -Recording $abandoned
            $file.FullName | Should -Be $abandoned.Path
            $abandoned.State | Should -Be 'Saved'
            $infoPath | Should -Not -Exist
            Should -Invoke Repair-ScreenRecording -ParameterFilter { $Path -eq $abandoned.RecordingPath -and $Force }
        }

        It 'Stops a running recording''s ffmpeg before repairing it' {
            $standInSplat = @{ FilePath = (Get-Process -Id $PID).Path; ArgumentList = '-NoProfile','-Command','Start-Sleep -Seconds 60'; PassThru = $true }
            if($IsWindows){ $standInSplat.WindowStyle = 'Hidden' }
            $stand_in = Start-Process @standInSplat
            try{
                $null = New-OtherInfoFile -ProcessId $stand_in.Id -ProcessStartTimeUtc $stand_in.StartTime.ToUniversalTime().ToString('o')
                $running = Get-OtherSessionRecording
                $running.State | Should -Be 'Recording'
                $null = Stop-OtherSessionRecording -Recording $running -Timeout ([timespan]::FromSeconds(5)) -WarningAction SilentlyContinue
                $stand_in.HasExited | Should -BeTrue
            }finally{
                if(!$stand_in.HasExited){ $stand_in.Kill($true) }
            }
        }

        It 'Marks the recording Failed when it can''t be repaired' {
            Mock Repair-ScreenRecording { throw 'nothing recoverable' }
            $null = New-OtherInfoFile -ProcessId 999998
            $abandoned = Get-OtherSessionRecording
            Stop-OtherSessionRecording -Recording $abandoned -ErrorAction SilentlyContinue
            $abandoned.State | Should -Be 'Failed'
        }

        It 'Does nothing with -WhatIf' {
            $null = New-OtherInfoFile -ProcessId 999998
            Stop-OtherSessionRecording -Recording (Get-OtherSessionRecording) -WhatIf
            Should -Invoke Repair-ScreenRecording -Times 0 -Exactly
        }
    }
}
