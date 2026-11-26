function Get-ScreenRecording
{
    <#
        .SYNOPSIS
            List this session's recordings, with how long each has run and how many frames it has

        .DESCRIPTION
            Returns every recording started in this PowerShell session, running or finished, with its latest
            figures from ffmpeg:

              State          Recording, Ended (its -Duration ran out; Stop-ScreenRecording saves it), Saved or Failed
              Elapsed        how much has been recorded
              Frames         frames recorded
              DroppedFrames  frames ffmpeg couldn't keep up with. A few is normal; many means the machine or
                             encoder is struggling, so try a lower -Fps, -Quality Standard, or a hardware -Encoder

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
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #Only the recordings with these Ids
        [Parameter(Position=0)]
        [int[]]$Id,
        #Only the recordings in these states
        [Parameter()]
        [ValidateSet('Recording','Ended','Saved','Failed')]
        [string[]]$State
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        if(!$script:psScreenRecorderRecordings)
        {
            return
        }
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
            if($State -and $recording.State -notin $State)
            {
                continue
            }
            $recording
        }
    }
}
