function Get-ScreenRecording
{
    <#
        .SYNOPSIS
            List recordings, with how long each has run and how many frames it has

        .DESCRIPTION
            Returns every recording started in this PowerShell session, running or finished, with its latest
            figures from ffmpeg:

              State          Recording, Ended (its -Duration ran out; Stop-ScreenRecording saves it), Saved or Failed
              Elapsed        how much has been recorded
              Frames         frames recorded
              DroppedFrames  frames ffmpeg couldn't keep up with. A few is normal; many means the machine or
                             encoder is struggling, so try a lower -Fps, -Quality Standard, or a hardware -Encoder

            -AllSessions adds recordings from other PowerShell sessions, with Session set to Other:
              Recording      still running in that session
              Abandoned      left behind when that session ended or crashed without stopping it

            Pipe either kind to Stop-ScreenRecording to stop it, or finish it, and save it.

            More detail, such as the ffmpeg arguments and the capture source and encoder chosen, is in the
            other properties: Get-ScreenRecording | Format-List *

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-ScreenRecording

            #### DESCRIPTION
            Show every recording in this session.

        .EXAMPLE
            Get-ScreenRecording -State Recording | Select-Object Id,Elapsed,Frames,DroppedFrames

            #### DESCRIPTION
            Check how the running recordings are doing.

        .EXAMPLE
            Get-ScreenRecording -AllSessions -State Abandoned | Stop-ScreenRecording

            #### DESCRIPTION
            Repair and save every recording other sessions left behind.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #Only the recordings with these Ids. Recordings from other sessions have no Id
        [Parameter(Position=0)]
        [int[]]$Id,
        #Only the recordings in these states
        [Parameter()]
        [ValidateSet('Recording','Ended','Saved','Failed','Abandoned')]
        [string[]]$State,
        #Include recordings from other PowerShell sessions, running or left behind
        [Parameter()]
        [switch]$AllSessions
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        $found = [System.Collections.Generic.List[object]]::new()
        if($script:psScreenRecorderRecordings)
        {
            foreach($recording in @($script:psScreenRecorderRecordings))
            {
                if($Id -and $recording.Id -notin $Id)
                {
                    continue
                }
                if($recording.State -in 'Recording','Ended')
                {
                    $null = Update-ScreenRecordingState -Recording $recording
                }
                $found.Add($recording)
            }
        }
        if($AllSessions -and !$Id)
        {
            foreach($other in Get-OtherSessionRecording)
            {
                $found.Add($other)
            }
        }
        foreach($recording in $found)
        {
            if($State -and $recording.State -notin $State)
            {
                continue
            }
            $recording
        }
    }
}
