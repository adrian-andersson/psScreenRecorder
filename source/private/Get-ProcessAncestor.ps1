function Get-ProcessAncestor
{
    <#
        .SYNOPSIS
            List a process and the processes that started it, nearest first

        .DESCRIPTION
            Follows each process's Parent up the tree. For pwsh inside Windows Terminal this gives something like
            pwsh, then WindowsTerminal; inside VS Code, pwsh then several Code processes.

            Stops after 32 steps, in case a parent ID has been reused and the chain loops.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-ProcessAncestor | Select-Object Id,ProcessName

            #### DESCRIPTION
            Show the chain of processes this PowerShell session runs under.
    #>

    [CmdletBinding()]
    PARAM(
        #Process to start from. Defaults to this PowerShell session
        [Parameter()]
        [int]$ProcessId = $PID
    )
    begin{
        $maximumDepth = 32
    }
    process{
        $current = Get-Process -Id $ProcessId -ErrorAction Ignore
        $seen = [System.Collections.Generic.HashSet[int]]::new()
        while($current -and $seen.Count -lt $maximumDepth -and $seen.Add($current.Id))
        {
            $current
            $current = $current.Parent
        }
    }
}
