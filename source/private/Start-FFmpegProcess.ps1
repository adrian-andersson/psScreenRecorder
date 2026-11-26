function Start-FFmpegProcess
{
    <#
        .SYNOPSIS
            Start a long-running ffmpeg, keeping hold of it so it can be stopped cleanly later

        .DESCRIPTION
            Invoke-FFmpeg runs ffmpeg to completion. A recording runs until it's told to stop, so this starts
            ffmpeg as a System.Diagnostics.Process instead, with all three standard streams redirected:

              stdin   kept open. Writing 'q' to it makes ffmpeg finish the file and exit cleanly. Version 1.0.14
                      sent the 'q' as a keypress with WScript.Shell.SendKeys, which went to whichever window had
                      focus, if focus had moved
              stdout  and stderr are read in the background by .NET (ReadToEndAsync), so ffmpeg never blocks on
                      a full pipe, and no PowerShell code has to run on another thread

            Arguments are passed through ProcessStartInfo.ArgumentList, one per element, so nothing is quoted.

            The process is tied to this PowerShell session with Register-ProcessCleanup, so it can't keep
            recording after the session ends.

            Returns an object holding the process and the two background reads, for Stop-FFmpegProcess.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            $handle = Start-FFmpegProcess -FFmpegPath (Find-FFmpeg).FFmpegPath -ArgumentList '-f','lavfi','-i','testsrc2','-f','null','-'
            Stop-FFmpegProcess -Handle $handle

            #### DESCRIPTION
            Start ffmpeg encoding a test pattern to nowhere, then stop it.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    PARAM(
        #Full path to ffmpeg
        [Parameter(Mandatory)]
        [string]$FFmpegPath,
        #Arguments, one element per argument
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$ArgumentList
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($FFmpegPath)
        foreach($argument in $ArgumentList)
        {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        write-verbose "Starting: $FFmpegPath $($ArgumentList -join ' ')"

        if($PSCmdlet.ShouldProcess($FFmpegPath, 'Start ffmpeg'))
        {
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $null = Register-ProcessCleanup -Process $process
            [PSCustomObject]@{
                PSTypeName = 'psScreenRecorder.FFmpegProcess'
                Process = $process
                ProcessId = $process.Id
                StandardOutputTask = $process.StandardOutput.ReadToEndAsync()
                StandardErrorTask = $process.StandardError.ReadToEndAsync()
                StartTime = [datetime]::Now
            }
        }
    }
}
