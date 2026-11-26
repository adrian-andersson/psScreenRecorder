function Wait-ScreenRecordingStop
{
    <#
        .SYNOPSIS
            Wait while a recording runs, until it's time to stop it

        .DESCRIPTION
            Used by Start-ScreenRecording -Wait and the focus modes. Waits for one of:
              Exit         ffmpeg exits by itself, which it does when a -Duration runs out
              Key          Q, Enter or Escape is pressed in the console, or ffmpeg exits
              FocusReturn  focus comes back to the terminal after leaving it, or ffmpeg exits

            Shows the elapsed time and frame count with Write-Progress while waiting.

            Returns why the wait ended: Exited, Key or Focus.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Wait-ScreenRecordingStop -Recording $recording -Mode Key

            #### DESCRIPTION
            Wait until Q, Enter or Escape is pressed.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    PARAM(
        #The recording
        [Parameter(Mandatory)]
        [PSCustomObject]$Recording,
        #What ends the wait
        [Parameter(Mandatory)]
        [ValidateSet('Exit','Key','FocusReturn')]
        [string]$Mode,
        #The terminal window, for FocusReturn
        [Parameter()]
        [long]$WindowHandle,
        #How often to check
        [Parameter()]
        [ValidateRange(10,5000)]
        [int]$PollMilliseconds = 200
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $activity = "Recording to $([System.IO.Path]::GetFileName($Recording.Path))"
        $hint = switch($Mode)
        {
            'Key' { 'Press Q, Enter or Escape to stop' }
            'FocusReturn' { 'Switch back to this window to stop' }
            'Exit' { "Stops after $($Recording.Duration)" }
        }
    }
    process{
        $process = $Recording.Handle.Process
        $hasLeft = $false
        try{
            while($true)
            {
                if($process.HasExited)
                {
                    return 'Exited'
                }
                if($Mode -eq 'Key' -and (Test-StopKeyPressed))
                {
                    return 'Key'
                }
                if($Mode -eq 'FocusReturn')
                {
                    $focused = (Get-ForegroundWindowHandle) -eq $WindowHandle
                    if(!$focused)
                    {
                        $hasLeft = $true
                    }elseif($hasLeft){
                        return 'Focus'
                    }
                }
                $null = Update-ScreenRecordingState -Recording $Recording
                $status = "$hint. $(if($Recording.Elapsed){$Recording.Elapsed.ToString('hh\:mm\:ss')}else{'00:00:00'}), $([int]$Recording.Frames) frames"
                if($Recording.DroppedFrames)
                {
                    $status = "$status, $($Recording.DroppedFrames) dropped"
                }
                Write-Progress -Activity $activity -Status $status
                Start-Sleep -Milliseconds $PollMilliseconds
            }
        }finally{
            Write-Progress -Activity $activity -Completed
        }
    }
}
