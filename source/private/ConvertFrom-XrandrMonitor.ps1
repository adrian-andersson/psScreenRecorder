function ConvertFrom-XrandrMonitor
{
    <#
        .SYNOPSIS
            Read X11 monitors from the output of 'xrandr --listmonitors', or 'xdpyinfo' as a fallback

        .DESCRIPTION
            xrandr --listmonitors prints one line per monitor:
                 0: +*DP-1 2560/597x1440/336+0+0  DP-1
            which is index, primary (*), name, width/mm x height/mm, then +x+y.

            xdpyinfo only knows the whole screen:
                  dimensions:    1280x1024 pixels (339x271 millimeters)
            which is what Xvfb, the virtual display used on headless machines, gives.

            Returns monitor capture targets on the given display.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            ConvertFrom-XrandrMonitor -XrandrOutput (xrandr --listmonitors) -Display ':0.0'

            #### DESCRIPTION
            List the monitors on display :0.0.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #Lines from xrandr --listmonitors
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$XrandrOutput,
        #Lines from xdpyinfo, used when xrandr gave nothing
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$XdpyinfoOutput,
        #The X11 display, such as :0.0
        [Parameter(Mandatory)]
        [string]$Display
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $monitorPattern = '^\s*(?<index>\d+):\s+\+?(?<primary>\*)?(?<name>\S+)\s+(?<width>\d+)/\d+x(?<height>\d+)/\d+\+(?<x>-?\d+)\+(?<y>-?\d+)'
    }
    process{
        $found = 0
        foreach($line in $XrandrOutput)
        {
            if($line -match $monitorPattern)
            {
                $found++
                $targetSplat = @{
                    Kind = 'Monitor'
                    Index = [int]$Matches.index
                    Name = $Matches.name
                    X = [int]$Matches.x
                    Y = [int]$Matches.y
                    Width = [int]$Matches.width
                    Height = [int]$Matches.height
                    IsPrimary = [bool]$Matches.primary
                    Display = $Display
                }
                New-CaptureTarget @targetSplat
            }
        }
        if($found -gt 0)
        {
            return
        }

        write-verbose 'No monitors from xrandr, using the screen size from xdpyinfo'
        $dimensions = $XdpyinfoOutput | Where-Object { $_ -match '^\s*dimensions:\s+(?<width>\d+)x(?<height>\d+) pixels' } | Select-Object -First 1
        $screenSplat = @{
            Kind = 'Monitor'
            Index = 0
            Name = "Screen $Display"
            X = 0
            Y = 0
            IsPrimary = $true
            Display = $Display
        }
        if($dimensions -and $dimensions -match '^\s*dimensions:\s+(?<width>\d+)x(?<height>\d+) pixels')
        {
            $screenSplat.Width = [int]$Matches.width
            $screenSplat.Height = [int]$Matches.height
        }
        New-CaptureTarget @screenSplat
    }
}
