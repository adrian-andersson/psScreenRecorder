function Get-NativeWindowInfo
{
    <#
        .SYNOPSIS
            List Windows windows in physical pixels, or get one by handle, using the native helper

        .DESCRIPTION
            A thin wrapper around the native helper's GetWindows() and GetWindow(), so the rest of the
            module can be tested by mocking this function instead of a Windows API.

            Without -Handle, lists visible top-level windows that have a title, top of the z-order first.
            With -Handle, returns that window, whatever its state, or nothing if it no longer exists.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-NativeWindowInfo | Select-Object -First 5

            #### DESCRIPTION
            The five windows nearest the top.
    #>

    [CmdletBinding()]
    [OutputType([object],[object[]])]
    PARAM(
        #A window handle (HWND) to look up
        [Parameter()]
        [long]$Handle
    )
    process{
        $native = Initialize-ScreenRecorderNative
        if($PSBoundParameters.ContainsKey('Handle'))
        {
            $native::GetWindow($Handle)
        }else{
            $native::GetWindows()
        }
    }
}
