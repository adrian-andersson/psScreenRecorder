function Test-StopKeyPressed
{
    <#
        .SYNOPSIS
            Check, without waiting, whether Q, Enter or Escape has been pressed in the console

        .DESCRIPTION
            Used by Start-ScreenRecording -Wait. Reads any waiting keypresses, so they don't end up typed at
            the prompt afterwards. Returns $false if console input is redirected, as there are no keys to read.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Test-StopKeyPressed

            #### DESCRIPTION
            Returns $true if Q, Enter or Escape was pressed since the last check.
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    PARAM()
    process{
        if([Console]::IsInputRedirected)
        {
            return $false
        }
        while([Console]::KeyAvailable)
        {
            $key = [Console]::ReadKey($true)
            if($key.Key -in [ConsoleKey]::Q,[ConsoleKey]::Enter,[ConsoleKey]::Escape)
            {
                return $true
            }
        }
        $false
    }
}
