function Stop-FFmpegProcess
{
    <#
        .SYNOPSIS
            Stop an ffmpeg started by Start-FFmpegProcess, letting it finish its file first

        .DESCRIPTION
            Writes 'q' to ffmpeg's stdin, which is ffmpeg's own way of being asked to stop: it stops reading
            input, writes what it has, closes the file and exits. Then waits for it to exit.

            If it hasn't exited after -Timeout, it's killed. A recording made into a Matroska (.mkv) file is
            still readable after that, which is why recordings are made into .mkv first.

            If ffmpeg has already exited, for example because a -Duration ran out, nothing is sent.

            Returns the exit code, everything ffmpeg wrote to stderr, and whether it had to be killed.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Stop-FFmpegProcess -Handle $handle -Timeout (New-TimeSpan -Seconds 30)

            #### DESCRIPTION
            Ask ffmpeg to stop, and give it 30 seconds to finish writing.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    PARAM(
        #What Start-FFmpegProcess returned
        [Parameter(Mandatory)]
        [PSCustomObject]$Handle,
        #How long to wait for ffmpeg to finish after asking it to stop
        [Parameter()]
        [timespan]$Timeout = [timespan]::FromSeconds(20)
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        $process = $Handle.Process
        $killed = $false
        if(!$process.HasExited)
        {
            if($PSCmdlet.ShouldProcess("ffmpeg ($($Handle.ProcessId))", 'Stop'))
            {
                write-verbose 'Asking ffmpeg to stop'
                try{
                    $process.StandardInput.Write('q')
                    $process.StandardInput.Flush()
                }catch{
                    write-verbose "Unable to write to ffmpeg, it may be exiting already: $($_.Exception.Message)"
                }
                if(!$process.WaitForExit([int]$Timeout.TotalMilliseconds))
                {
                    Write-Warning "ffmpeg did not stop within $($Timeout.TotalSeconds) seconds, so it was ended. The recording up to that point should still be readable"
                    try{
                        $process.Kill($true)
                    }catch{
                        write-verbose "Kill failed, it may have just exited: $($_.Exception.Message)"
                    }
                    $killed = $true
                }
            }else{
                return
            }
        }
        #Wait once more without a timeout, which also waits for the redirected output to be read to the end
        $process.WaitForExit()

        [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.FFmpegExit'
            ExitCode = $process.ExitCode
            StandardError = $Handle.StandardErrorTask.GetAwaiter().GetResult()
            Killed = $killed
        }
    }
}
