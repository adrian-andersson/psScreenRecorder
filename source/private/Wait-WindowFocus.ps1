function Wait-WindowFocus
{
    <#
        .SYNOPSIS
            Wait until a window loses focus, or gets it back

        .DESCRIPTION
            The focus modes of Start-ScreenRecording: recording starts when you switch away from the terminal,
            and stops when you come back to it.

            -Until Lost waits until any other window has focus.
            -Until Returned waits until the window has focus again, after first having lost it. Without that
            first step, recording would stop immediately, as the terminal has focus when the command starts.

            -Process stops the wait early if that process exits, for example when a -Duration runs out.

            Returns $true when focus changed as asked, $false if the process exited first.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Wait-WindowFocus -WindowHandle (Get-TerminalWindowHandle) -Until Lost

            #### DESCRIPTION
            Wait until you switch to another window.
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    PARAM(
        #The window to watch
        [Parameter(Mandatory)]
        [long]$WindowHandle,
        #What to wait for
        [Parameter(Mandatory)]
        [ValidateSet('Lost','Returned')]
        [string]$Until,
        #Stop waiting if this process exits
        [Parameter()]
        [System.Diagnostics.Process]$Process,
        #How often to check
        [Parameter()]
        [ValidateRange(10,5000)]
        [int]$PollMilliseconds = 100
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        $hasLeft = $Until -eq 'Lost'
        while($true)
        {
            if($Process -and $Process.HasExited)
            {
                write-verbose 'The process exited while waiting for focus to change'
                return $false
            }
            $focused = (Get-ForegroundWindowHandle) -eq $WindowHandle
            if($Until -eq 'Lost' -and !$focused)
            {
                write-verbose 'Focus left the window'
                return $true
            }
            if($Until -eq 'Returned')
            {
                if(!$focused)
                {
                    $hasLeft = $true
                }elseif($hasLeft){
                    write-verbose 'Focus came back to the window'
                    return $true
                }
            }
            Start-Sleep -Milliseconds $PollMilliseconds
        }
    }
}
