function Register-ScreenRecorderExitHandler
{
    <#
        .SYNOPSIS
            Make sure recordings are stopped, not left running, when PowerShell exits

        .DESCRIPTION
            Registers, once per session, a handler for the PowerShell.Exiting engine event that sends 'q' to
            every ffmpeg still recording and gives it a few seconds to finish its file.

            There's no time to save the final file while PowerShell is exiting, so the recording is left as its
            .recording.mkv file, which plays as it is.

            The recordings list is passed to the handler as its message data, so the handler doesn't depend on
            which scope it runs in.

        .NOTES
            Author: Adrian Andersson

            PowerShell.Exiting is only raised when an interactive session exits, not when a -Command or script
            session ends, and not on a crash. Register-ProcessCleanup covers those, at the operating system
            level. This handler is the gentler path where it does fire: ffmpeg gets 'q' and finishes the file.

        .EXAMPLE
            Register-ScreenRecorderExitHandler -Recordings $script:psScreenRecorderRecordings

            #### DESCRIPTION
            Called by Start-ScreenRecording. Does nothing if already registered.
    #>

    [CmdletBinding()]
    PARAM(
        #The list of recordings to stop on exit
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Recordings
    )
    process{
        if($script:psScreenRecorderExitSubscriber)
        {
            write-verbose 'Exit handler already registered'
            return
        }
        $registerSplat = @{
            SourceIdentifier = [System.Management.Automation.PsEngineEvent]::Exiting
            MessageData = $Recordings
            #Keep it out of Get-EventSubscriber and Get-Job, where it would only confuse
            SupportEvent = $true
            Action = {
                foreach($recording in $Event.MessageData)
                {
                    try{
                        $process = $recording.Handle.Process
                        if($process -and !$process.HasExited)
                        {
                            $process.StandardInput.Write('q')
                            $process.StandardInput.Flush()
                            $null = $process.WaitForExit(5000)
                        }
                    }catch{
                        #Exiting anyway, and Register-ProcessCleanup ends ffmpeg if this didn't
                        $null = $_
                    }
                }
            }
        }
        $null = Register-EngineEvent @registerSplat
        $script:psScreenRecorderExitSubscriber = $true
        write-verbose 'Exit handler registered'
    }
}
