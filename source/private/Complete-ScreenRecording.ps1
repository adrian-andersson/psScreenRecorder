function Complete-ScreenRecording
{
    <#
        .SYNOPSIS
            Turn a stopped recording into its final file

        .DESCRIPTION
            Recordings are made into a Matroska (.mkv) file next to the final one, as Matroska stays readable
            even if ffmpeg is killed part way through. Once ffmpeg has stopped, this:
              - checks ffmpeg exited cleanly, or was stopped, and that something was recorded
              - for an .mkv destination, renames the recording into place
              - otherwise, copies the video into the final container without re-encoding (a remux, which takes
                moments), with the index at the start (+faststart) so it plays while still downloading. HEVC
                is tagged hvc1, which Apple players need
              - removes the recording file and the progress file

            If the remux fails, the .mkv is kept, and its path is in the error.

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

        if($ExitInfo.ExitCode -ne 0 -and !$ExitInfo.Killed)
        {
            $Recording.State = 'Failed'
            $Recording.Error = "ffmpeg exited with code $($ExitInfo.ExitCode): $errorText"
            if($hasVideo)
            {
                $Recording.Error = "$($Recording.Error). What was recorded is in: $($Recording.RecordingPath)"
            }else{
                Remove-Item -LiteralPath $Recording.RecordingPath -Force -ErrorAction Ignore
            }
            Write-Error -Message "The recording failed. $($Recording.Error)"
            return
        }
        if(!$hasVideo)
        {
            $Recording.State = 'Failed'
            $Recording.Error = "Nothing was recorded. $errorText".Trim()
            Remove-Item -LiteralPath $Recording.RecordingPath -Force -ErrorAction Ignore
            Write-Error -Message "The recording failed. $($Recording.Error)"
            return
        }

        $extension = [System.IO.Path]::GetExtension($Recording.Path).ToLowerInvariant()
        if($extension -eq '.mkv')
        {
            write-verbose 'Destination is Matroska, renaming the recording into place'
            Move-Item -LiteralPath $Recording.RecordingPath -Destination $Recording.Path -Force -ErrorAction Stop
        }else{
            write-verbose "Remuxing into $extension"
            $remuxArguments = [System.Collections.Generic.List[string]]::new()
            $remuxArguments.AddRange([string[]]@('-hide_banner','-loglevel','error','-y','-i',$Recording.RecordingPath,'-map','0','-c','copy','-movflags','+faststart'))
            if($Recording.Codec -eq 'HEVC')
            {
                $remuxArguments.AddRange([string[]]@('-tag:v','hvc1'))
            }
            $remuxArguments.Add($Recording.Path)
            try{
                $null = Invoke-FFmpeg -ArgumentList $remuxArguments -ErrorAction Stop
            }catch{
                $Recording.State = 'Failed'
                $Recording.Error = "Unable to save as $($extension): $($_.Exception.Message). The recording is kept in: $($Recording.RecordingPath)"
                Write-Error -Message $Recording.Error
                return
            }
            Remove-Item -LiteralPath $Recording.RecordingPath -Force -ErrorAction Ignore
        }

        $Recording.State = 'Saved'
        $file = Get-Item -LiteralPath $Recording.Path
        try{
            $metadata = Get-VideoMetadata -Path $file.FullName -ErrorAction Stop
            foreach($property in 'Duration','Width','Height','FrameRate','VideoCodec')
            {
                $file | Add-Member -NotePropertyName $property -NotePropertyValue $metadata.$property -Force
            }
            $Recording.Elapsed = $metadata.Duration
        }catch{
            write-verbose "Unable to read the saved recording's details: $($_.Exception.Message)"
        }
        $file
    }
}
