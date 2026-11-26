function Register-ProcessCleanup
{
    <#
        .SYNOPSIS
            Make sure a child process doesn't outlive this PowerShell session

        .DESCRIPTION
            ffmpeg keeps recording until it's told to stop. It ignores its stdin closing, and PowerShell's
            Exiting event doesn't fire for every way a session can end (a script run with -Command, a crash,
            closing the window), so without this, a recording can carry on forever with nobody to stop it.

              Windows        the process goes into a Job Object that ends it when this process ends, however
                             it ends. Windows does this itself, so it works even if PowerShell crashes
              macOS, Linux   a small sh watchdog checks both processes every second. If this PowerShell
                             process has gone, it sends ffmpeg SIGINT, ffmpeg's own clean stop, so the file
                             is finished properly. It ignores hangups, so it outlives a closed terminal, and it
                             exits as soon as the process it's watching does

            The recording is made into Matroska, so even an abrupt end leaves a readable file.

            Returns $true if the cleanup was set up.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Register-ProcessCleanup -Process $handle.Process

            #### DESCRIPTION
            End ffmpeg when this PowerShell session ends.
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    PARAM(
        #The child process
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        #$1 is this PowerShell process, $2 the child. Ignoring HUP lets it outlive a closed terminal
        $watchdogScript = 'trap "" HUP; while kill -0 "$1" 2>/dev/null && kill -0 "$2" 2>/dev/null; do sleep 1; done; if kill -0 "$2" 2>/dev/null; then kill -INT "$2"; fi'
    }
    process{
        if($IsWindows)
        {
            try{
                Initialize-ScreenRecorderNative
                $assigned = [PsScreenRecorder.Native]::KillWithThisProcess($Process.Handle)
                write-verbose "Added process $($Process.Id) to the cleanup job: $assigned"
                return $assigned
            }catch{
                Write-Warning "Unable to tie ffmpeg to this session, so it may keep running if PowerShell ends without stopping it: $($_.Exception.Message)"
                return $false
            }
        }

        $shell = Get-Command -Name 'sh' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
        if(!$shell)
        {
            Write-Warning 'sh was not found, so ffmpeg may keep running if PowerShell ends without stopping it'
            return $false
        }
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new($shell.Source)
        foreach($argument in @('-c',$watchdogScript,'psScreenRecorder-watchdog',[string]$PID,[string]$Process.Id))
        {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $watchdog = [System.Diagnostics.Process]::Start($startInfo)
        write-verbose "Started watchdog $($watchdog.Id) for process $($Process.Id)"
        $true
    }
}
