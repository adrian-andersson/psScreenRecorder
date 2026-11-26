function Stop-OtherSessionRecording
{
    <#
        .SYNOPSIS
            Stop a recording another PowerShell session started, or finish one it left behind, and save it

        .DESCRIPTION
            This session doesn't hold the other ffmpeg's stdin, so it can't send 'q'. Instead:
              macOS, Linux  ffmpeg is sent SIGINT, its own clean stop, the same as 'q'
              Windows       ffmpeg is ended, as Windows has no equivalent signal to send another console
                            process. Matroska survives this, losing at most the last second

            Then the recording is repaired into its final file with a remux, which rebuilds the index an
            unclean stop leaves out, and the info and progress files are removed.

            An abandoned recording, whose ffmpeg has already gone, is just repaired.

            Returns the saved file.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-OtherSessionRecording | ForEach-Object { Stop-OtherSessionRecording -Recording $_ }

            #### DESCRIPTION
            Stop and save everything other sessions are recording or left behind.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    PARAM(
        #A recording from Get-OtherSessionRecording
        [Parameter(Mandatory)]
        [PSCustomObject]$Recording,
        #How long to wait for ffmpeg to stop
        [Parameter()]
        [timespan]$Timeout = [timespan]::FromSeconds(20)
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        if(!$PSCmdlet.ShouldProcess($Recording.Path, "Stop the recording another session started, and save it"))
        {
            return
        }
        if($Recording.State -eq 'Recording')
        {
            $process = Get-Process -Id $Recording.ProcessId -ErrorAction Ignore
            if($process)
            {
                if($IsWindows)
                {
                    write-verbose "Ending ffmpeg $($Recording.ProcessId)"
                    Stop-Process -Id $Recording.ProcessId -Force -ErrorAction SilentlyContinue
                }else{
                    write-verbose "Sending SIGINT to ffmpeg $($Recording.ProcessId)"
                    & /bin/kill -s INT $Recording.ProcessId 2>$null
                }
                if(!$process.WaitForExit([int]$Timeout.TotalMilliseconds))
                {
                    Write-Warning "ffmpeg $($Recording.ProcessId) did not stop within $($Timeout.TotalSeconds) seconds, so it was ended"
                    Stop-Process -Id $Recording.ProcessId -Force -ErrorAction SilentlyContinue
                    $null = $process.WaitForExit(5000)
                }
            }
        }

        try{
            $file = Repair-ScreenRecording -Path $Recording.RecordingPath -Destination $Recording.Path -Codec $Recording.Codec -Force -ErrorAction Stop
        }catch{
            $Recording.State = 'Failed'
            $Recording.Error = $_.Exception.Message
            Write-Error -Message "Unable to save the recording from the other session: $($_.Exception.Message)"
            return
        }
        foreach($leftover in @($Recording.InfoPath, $Recording.ProgressPath))
        {
            if($leftover)
            {
                Remove-Item -LiteralPath $leftover -Force -ErrorAction Ignore
            }
        }
        $Recording.State = 'Saved'
        $file
    }
}
