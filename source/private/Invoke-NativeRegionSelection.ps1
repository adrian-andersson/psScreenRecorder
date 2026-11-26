function Invoke-NativeRegionSelection
{
    <#
        .SYNOPSIS
            Show the Windows region selection overlay, and return what was selected

        .DESCRIPTION
            A thin wrapper around the native helper's SelectRegion(), so Select-ScreenRegion can be tested
            by mocking this function.

            Returns [x, y, width, height] in physical pixels on the virtual desktop, or nothing if cancelled.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Invoke-NativeRegionSelection

            #### DESCRIPTION
            Dims every monitor, waits for a drag, and returns the area.
    #>

    [CmdletBinding()]
    [OutputType([System.Array])]
    PARAM()
    process{
        $native = Initialize-ScreenRecorderNative
        $selection = $native::SelectRegion()
        if($selection)
        {
            ,$selection
        }
    }
}
