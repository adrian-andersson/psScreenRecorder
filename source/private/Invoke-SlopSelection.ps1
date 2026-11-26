function Invoke-SlopSelection
{
    <#
        .SYNOPSIS
            Let the person drag out an area on X11 with slop, and return it

        .DESCRIPTION
            slop prints the selection in the format asked for, here 'x y width height'. It exits with an error
            when cancelled with Esc or a right-click.

            Returns [x, y, width, height], or nothing if cancelled.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Invoke-SlopSelection

            #### DESCRIPTION
            Returns something like 100, 200, 800, 600.
    #>

    [CmdletBinding()]
    [OutputType([System.Array])]
    PARAM()
    process{
        $output = & slop --format '%x %y %w %h' 2>$null
        if($LASTEXITCODE -ne 0 -or !$output)
        {
            write-verbose 'slop was cancelled'
            return
        }
        $values = ([string]($output | Select-Object -Last 1)).Trim() -split '\s+'
        if($values.Count -ne 4 -or ($values | Where-Object { $_ -notmatch '^-?\d+$' }))
        {
            throw "slop returned something unexpected: $output"
        }
        ,[int[]]$values
    }
}
