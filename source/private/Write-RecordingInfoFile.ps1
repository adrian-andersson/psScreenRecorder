function Write-RecordingInfoFile
{
    <#
        .SYNOPSIS
            Save what another PowerShell session needs to find, stop or repair a recording

        .DESCRIPTION
            Writes a small JSON file to the 'recordings' folder in the cache folder (see
            Get-ScreenRecorderCacheFolder): ffmpeg's process ID and start time, the session that started it, and
            the recording, final and progress file paths. Get-ScreenRecording -AllSessions reads these.

            The start time guards against process IDs being reused: a process with the same ID but a different
            start time is a different process.

            Complete-ScreenRecording removes the file once the recording is saved. Returns the file's path.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            $recording.InfoPath = Write-RecordingInfoFile -Recording $recording

            #### DESCRIPTION
            Record where the recording is, so another session can find it.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    PARAM(
        #The recording, from Start-ScreenRecording
        [Parameter(Mandatory)]
        [PSCustomObject]$Recording
    )
    process{
        $folder = Join-Path -Path (Get-ScreenRecorderCacheFolder) -ChildPath 'recordings'
        if(!(Test-Path -LiteralPath $folder -PathType Container))
        {
            $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop
        }
        $processStart = $null
        try{
            $processStart = $Recording.Handle.Process.StartTime.ToUniversalTime().ToString('o')
        }catch{
            write-verbose "Unable to read ffmpeg's start time: $($_.Exception.Message)"
        }
        $info = [ordered]@{
            ProcessId = $Recording.ProcessId
            ProcessStartTimeUtc = $processStart
            OwnerProcessId = $PID
            TargetName = $Recording.TargetName
            Path = $Recording.Path
            RecordingPath = $Recording.RecordingPath
            ProgressPath = $Recording.ProgressPath
            Codec = $Recording.Codec
            Backend = $Recording.Backend
            Encoder = $Recording.Encoder
            StartTimeUtc = $Recording.StartTime.ToUniversalTime().ToString('o')
        }
        $infoPath = Join-Path -Path $folder -ChildPath "$($Recording.ProcessId)-$([guid]::NewGuid().ToString('N').Substring(0,8)).json"
        ConvertTo-Json -InputObject $info | Set-Content -LiteralPath $infoPath -Encoding utf8NoBOM -ErrorAction Stop
        $infoPath
    }
}
