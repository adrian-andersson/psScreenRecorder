function Update-ScreenRecordingState
{
    <#
        .SYNOPSIS
            Refresh a recording's state and statistics from its ffmpeg process and progress file

        .DESCRIPTION
            Copies the latest frame count, dropped and duplicated frames, elapsed time, size and speed from the
            progress file onto the recording. A recording whose ffmpeg has exited by itself, for example when a
            -Duration ran out, changes from Recording to Ended: it still needs Stop-ScreenRecording to save it.

            Returns the recording.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Update-ScreenRecordingState -Recording $recording

            #### DESCRIPTION
            Bring the recording's statistics up to date.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only updates an object in memory')]
    PARAM(
        #The recording
        [Parameter(Mandatory)]
        [PSCustomObject]$Recording
    )
    process{
        $progress = Read-FFmpegProgress -Path $Recording.ProgressPath
        if($progress)
        {
            $Recording.Frames = $progress.Frame
            $Recording.DroppedFrames = $progress.DroppedFrames
            $Recording.DuplicatedFrames = $progress.DuplicatedFrames
            $Recording.Elapsed = $progress.Elapsed
            $Recording.Size = $progress.Size
            $Recording.Speed = $progress.Speed
        }
        if($Recording.State -eq 'Recording' -and $Recording.Handle -and $Recording.Handle.Process.HasExited)
        {
            $Recording.State = 'Ended'
        }
        $Recording
    }
}
