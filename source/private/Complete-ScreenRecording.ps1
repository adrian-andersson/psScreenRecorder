function Complete-ScreenRecording
{
    <#
        .SYNOPSIS
            Turn a stopped recording into its final file

        .DESCRIPTION
            Recordings are made into a Matroska (.mkv) file next to the final one, as Matroska stays readable
            even if ffmpeg is killed part way through. Once ffmpeg has stopped, this:
              - checks something was recorded. If nothing was, the recording fails with ffmpeg's error
              - if ffmpeg ended unexpectedly part way through, warns, and saves what was recorded anyway
              - for a cleanly finished .mkv destination, renames the recording into place
              - otherwise, copies the video into the final container without re-encoding (a remux, which takes
                moments, see Convert-RecordingContainer). That also rebuilds the index of a recording that
                didn't finish cleanly
              - removes the recording, progress and info files

            If the remux fails, the .mkv is kept, its path is in the error, and Repair-ScreenRecording can try
            again.

            Returns the final file, with Duration, Width, Height, FrameRate and VideoCodec added from ffprobe.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Complete-ScreenRecording -Recording $recording -ExitInfo (Stop-FFmpegProcess -Handle $recording.Handle)

            #### DESCRIPTION
            Save a recording once ffmpeg has stopped.
    #>

    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    PARAM(
        #The recording, from Start-ScreenRecording
        [Parameter(Mandatory)]
        [PSCustomObject]$Recording,
        #What Stop-FFmpegProcess returned
        [Parameter(Mandatory)]
        [PSCustomObject]$ExitInfo
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $errorTailLength = 8
    }
    process{
        $Recording.EndTime = [datetime]::Now
        $errorText = (([string]$ExitInfo.StandardError) -split "`r?`n" | Where-Object { $_ } | Select-Object -Last $errorTailLength) -join [Environment]::NewLine
        $recordingFile = Get-Item -LiteralPath $Recording.RecordingPath -ErrorAction Ignore
        $hasVideo = $recordingFile -and $recordingFile.Length -gt 0

        if(Test-Path -LiteralPath $Recording.ProgressPath)
        {
            $null = Update-ScreenRecordingState -Recording $Recording
            Remove-Item -LiteralPath $Recording.ProgressPath -Force -ErrorAction Ignore
        }

        if($Recording.PSObject.Properties['InfoPath'] -and $Recording.InfoPath)
        {
            Remove-Item -LiteralPath $Recording.InfoPath -Force -ErrorAction Ignore
        }

        if(!$hasVideo)
        {
            $Recording.State = 'Failed'
            $Recording.Error = $(if($ExitInfo.ExitCode -ne 0 -and !$ExitInfo.Killed){"ffmpeg exited with code $($ExitInfo.ExitCode): $errorText"}else{"Nothing was recorded. $errorText".Trim()})
            Remove-Item -LiteralPath $Recording.RecordingPath -Force -ErrorAction Ignore
            Write-Error -Message "The recording failed. $($Recording.Error)"
            return
        }
        #Anything other than a clean finish leaves the Matroska file without its index, which a remux rebuilds
        $cleanFinish = $ExitInfo.ExitCode -eq 0 -and !$ExitInfo.Killed
        if(!$cleanFinish -and !$ExitInfo.Killed)
        {
            Write-Warning "ffmpeg ended unexpectedly (exit code $($ExitInfo.ExitCode)), so the recording may stop short. Saving what was recorded. ffmpeg said: $errorText"
        }

        $extension = [System.IO.Path]::GetExtension($Recording.Path).ToLowerInvariant()
        if($extension -eq '.mkv' -and $cleanFinish)
        {
            write-verbose 'Destination is Matroska, renaming the recording into place'
            Move-Item -LiteralPath $Recording.RecordingPath -Destination $Recording.Path -Force -ErrorAction Stop
        }else{
            write-verbose "Remuxing into $extension"
            try{
                Convert-RecordingContainer -Path $Recording.RecordingPath -Destination $Recording.Path -Codec $Recording.Codec
            }catch{
                $Recording.State = 'Failed'
                $Recording.Error = "Unable to save as $($extension): $($_.Exception.Message). The recording is kept in: $($Recording.RecordingPath). Repair-ScreenRecording can try again"
                Write-Error -Message $Recording.Error
                return
            }
            Remove-Item -LiteralPath $Recording.RecordingPath -Force -ErrorAction Ignore
        }

        $Recording.State = 'Saved'
        $file = Get-Item -LiteralPath $Recording.Path | Add-VideoMetadataMember
        if($file.PSObject.Properties['Duration'] -and $file.Duration)
        {
            $Recording.Elapsed = $file.Duration
        }
        $file
    }
}
