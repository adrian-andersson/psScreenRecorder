function Get-NativeMonitorInfo
{
    <#
        .SYNOPSIS
            List Windows monitors in physical pixels, using the native helper

        .DESCRIPTION
            A thin wrapper around [PsScreenRecorder.Native]::GetMonitors(), so the rest of the module can be
            tested by mocking this function instead of a Windows API.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-NativeMonitorInfo

            #### DESCRIPTION
            List every monitor's handle, device name, bounds, primary flag and DPI.
    #>

    [CmdletBinding()]
    [OutputType('PsScreenRecorder.MonitorInfo[]')]
    PARAM()
    process{
        Initialize-ScreenRecorderNative
        [PsScreenRecorder.Native]::GetMonitors()
    }
}
