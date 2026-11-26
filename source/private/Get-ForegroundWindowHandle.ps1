function Get-ForegroundWindowHandle
{
    <#
        .SYNOPSIS
            Get the handle of the window that has focus

        .DESCRIPTION
            A thin wrapper around the native helper's GetForegroundWindow(), so the focus modes of
            Start-ScreenRecording can be tested by mocking this function.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-ForegroundWindowHandle

            #### DESCRIPTION
            Returns the HWND of the focused window, as a number.
    #>

    [CmdletBinding()]
    [OutputType([long])]
    PARAM()
    process{
        $native = Initialize-ScreenRecorderNative
        $native::GetForegroundWindow()
    }
}
