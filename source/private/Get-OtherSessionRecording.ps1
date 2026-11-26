function Get-OtherSessionRecording
{
    <#
        .SYNOPSIS
            Find recordings started by other PowerShell sessions, from their info files

        .DESCRIPTION
            Reads the info files Write-RecordingInfoFile saves, skipping this session's own, and works out each
            recording's state:

              Recording   its ffmpeg is still running (same process ID and start time)
              Abandoned   its ffmpeg has gone, but the recording file is there to repair. This is what's left
                          when a session ends, or crashes, without stopping its recording

            An info file whose ffmpeg has gone and whose recording file is missing or empty is stale, and is
            deleted.

            Returns recording objects, with Session set to 'Other', that Stop-ScreenRecording accepts.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-OtherSessionRecording

            #### DESCRIPTION
            List recordings running in, or left behind by, other sessions.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM()
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $displayProperties = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]@('Id','State','Session','TargetName','Elapsed','Frames','Path'))
        $sameProcessTolerance = [timespan]::FromSeconds(2)
    }
    process{
        $folder = Join-Path -Path (Get-ScreenRecorderCacheFolder) -ChildPath 'recordings'
        if(!(Test-Path -LiteralPath $folder -PathType Container))
        {
            return
        }
        foreach($infoFile in Get-ChildItem -LiteralPath $folder -Filter '*.json' -File)
        {
            try{
                $info = Get-Content -LiteralPath $infoFile.FullName -Raw | ConvertFrom-Json -DateKind String -ErrorAction Stop
            }catch{
                write-verbose "Skipping unreadable info file: $($infoFile.Name)"
                continue
            }
            if([int]$info.OwnerProcessId -eq $PID)
            {
                continue
            }

            $running = $false
            $process = Get-Process -Id ([int]$info.ProcessId) -ErrorAction Ignore
            if($process)
            {
                $running = $true
                if($info.ProcessStartTimeUtc)
                {
                    try{
                        $expected = [datetime]::Parse($info.ProcessStartTimeUtc, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                        $running = [math]::Abs(($process.StartTime.ToUniversalTime() - $expected).TotalSeconds) -le $sameProcessTolerance.TotalSeconds
                    }catch{
                        write-verbose "Unable to compare start times for process $($info.ProcessId), assuming it is the same one"
                    }
                }
            }

            $recordingFile = Get-Item -LiteralPath $info.RecordingPath -ErrorAction Ignore
            if(!$running -and (!$recordingFile -or $recordingFile.Length -eq 0))
            {
                write-verbose "Removing stale info file: $($infoFile.Name)"
                Remove-Item -LiteralPath $infoFile.FullName -Force -ErrorAction Ignore
                continue
            }

            $recording = [PSCustomObject]@{
                PSTypeName = 'psScreenRecorder.Recording'
                Id = $null
                State = $(if($running){'Recording'}else{'Abandoned'})
                Session = 'Other'
                TargetName = $info.TargetName
                Elapsed = $null
                Frames = $null
                DroppedFrames = $null
                DuplicatedFrames = $null
                Size = $(if($recordingFile){$recordingFile.Length})
                Speed = $null
                Path = $info.Path
                RecordingPath = $info.RecordingPath
                ProgressPath = $info.ProgressPath
                InfoPath = $infoFile.FullName
                Codec = $info.Codec
                Backend = $info.Backend
                Encoder = $info.Encoder
                ProcessId = [int]$info.ProcessId
                OwnerProcessId = [int]$info.OwnerProcessId
                StartTime = $(try{ [datetime]::Parse($info.StartTimeUtc, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime() }catch{ $null })
                Error = $null
                Handle = $null
            }
            $recording | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value ([System.Management.Automation.PSMemberInfo[]]@($displayProperties))
            if($running -and $info.ProgressPath)
            {
                $progress = Read-FFmpegProgress -Path $info.ProgressPath
                if($progress)
                {
                    $recording.Frames = $progress.Frame
                    $recording.Elapsed = $progress.Elapsed
                    $recording.DroppedFrames = $progress.DroppedFrames
                }
            }
            $recording
        }
    }
}
