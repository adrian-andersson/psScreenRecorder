function Get-X11MonitorOutput
{
    <#
        .SYNOPSIS
            Ask X11 what monitors there are, with xrandr, or xdpyinfo if xrandr isn't installed

        .DESCRIPTION
            Runs 'xrandr --listmonitors' and, if that gives nothing, 'xdpyinfo', and returns their output for
            ConvertFrom-XrandrMonitor to read. Either tool can be missing; then its output is empty.

            Kept separate so Get-CaptureTarget can be tested without an X server.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-X11MonitorOutput

            #### DESCRIPTION
            Returns the raw xrandr and xdpyinfo output for the current DISPLAY.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM()
    process{
        $xrandrOutput = @()
        $xdpyinfoOutput = @()
        if(Get-Command -Name 'xrandr' -CommandType Application -ErrorAction Ignore)
        {
            $xrandrOutput = @(& xrandr --listmonitors 2>$null)
        }
        if(!$xrandrOutput -and (Get-Command -Name 'xdpyinfo' -CommandType Application -ErrorAction Ignore))
        {
            $xdpyinfoOutput = @(& xdpyinfo 2>$null)
        }
        [PSCustomObject]@{
            Xrandr = [string[]]$xrandrOutput
            Xdpyinfo = [string[]]$xdpyinfoOutput
        }
    }
}
