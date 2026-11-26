function New-RegionTarget
{
    <#
        .SYNOPSIS
            Make a capture target for an area of the screen, and find the monitor it sits inside

        .DESCRIPTION
            Used by Start-ScreenRecording -Rectangle and Select-ScreenRegion.

            Width and height are rounded down to even numbers, as most encoders need them even, rather than
            failing. Anything under 2 pixels either way throws.

            The monitor the area fits entirely inside is attached as the target's Monitor, so capture sources
            that work per monitor (gfxcapture, ddagrab, avfoundation) can crop it from that monitor. An area
            spanning monitors has no Monitor, and is recorded from the whole desktop. macOS doesn't report
            screen sizes, so there the area is taken to be on the main screen.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            New-RegionTarget -X 100 -Y 100 -Width 1281 -Height 721 -Monitors (Get-CaptureTarget)

            #### DESCRIPTION
            A 1280x720 region at 100,100, with the monitor it's on.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only builds an object, nothing is changed')]
    PARAM(
        #Left edge, in physical pixels
        [Parameter(Mandatory)]
        [int]$X,
        #Top edge, in physical pixels
        [Parameter(Mandatory)]
        [int]$Y,
        #Width, in physical pixels
        [Parameter(Mandatory)]
        [int]$Width,
        #Height, in physical pixels
        [Parameter(Mandatory)]
        [int]$Height,
        #The monitors, from Get-CaptureTarget
        [Parameter()]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$Monitors = @(),
        #The platform's rules to use. Defaults to this one
        [Parameter(DontShow)]
        [ValidateSet('Windows','macOS','Linux')]
        [string]$Platform = $(if($IsWindows){'Windows'}elseif($IsMacOS){'macOS'}else{'Linux'})
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        $evenWidth = $Width - ($Width % 2)
        $evenHeight = $Height - ($Height % 2)
        if($evenWidth -lt 2 -or $evenHeight -lt 2)
        {
            throw 'The area must be at least 2 pixels wide and high'
        }

        $containing = $(if($Platform -eq 'macOS'){
            $Monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
        }else{
            $Monitors | Where-Object {
                $null -ne $_.Width -and $X -ge $_.X -and $Y -ge $_.Y -and ($X + $evenWidth) -le ($_.X + $_.Width) -and ($Y + $evenHeight) -le ($_.Y + $_.Height)
            } | Select-Object -First 1
        })

        $regionSplat = @{
            Kind = 'Region'
            Name = "$($evenWidth)x$($evenHeight) at $X,$Y"
            X = $X
            Y = $Y
            Width = $evenWidth
            Height = $evenHeight
            Monitor = $containing
        }
        New-CaptureTarget @regionSplat
    }
}
