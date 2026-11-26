function Get-TerminalWindowHandle
{
    <#
        .SYNOPSIS
            Work out which window this PowerShell session is running in

        .DESCRIPTION
            Used by -CurrentTerminal and the focus modes. Windows only.

            Version 1 looked for a powershell process with a main window. Under Windows Terminal or VS Code
            no PowerShell process has a window of its own, so it found nothing, and recording never stopped.

            This checks, in order:
              1. The focused window, if it belongs to this session or one of the processes that started it.
                 When a command is typed, the terminal it was typed into has focus, so this is the usual answer
              2. The nearest of those processes that has a main window, such as WindowsTerminal or Code

            Returns the window handle, or throws if neither finds one, for example in a session with no window.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-TerminalWindowHandle

            #### DESCRIPTION
            Returns the HWND of the terminal window this command was typed into.
    #>

    [CmdletBinding()]
    [OutputType([long])]
    PARAM()
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        $ancestors = @(Get-ProcessAncestor)
        $ancestorIds = @($ancestors.Id)
        write-verbose "Process chain: $(($ancestors | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ' <- ')"

        $foreground = Get-ForegroundWindowHandle
        if($foreground)
        {
            $foregroundWindow = Get-NativeWindowInfo -Handle $foreground
            if($foregroundWindow -and $foregroundWindow.ProcessId -in $ancestorIds)
            {
                write-verbose "The focused window belongs to this session: $($foregroundWindow.Title)"
                return [long]$foreground
            }
        }

        foreach($ancestor in $ancestors)
        {
            if($ancestor.MainWindowHandle -and [long]$ancestor.MainWindowHandle -ne 0)
            {
                write-verbose "Using the main window of $($ancestor.ProcessName) ($($ancestor.Id))"
                return [long]$ancestor.MainWindowHandle
            }
        }

        throw 'Unable to find the window this PowerShell session is running in. Run the command from a terminal window, or record a window with -Window instead'
    }
}
