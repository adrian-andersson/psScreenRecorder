function New-CaptureTarget
{
    <#
        .SYNOPSIS
            Make a capture target: what Start-ScreenRecording records

        .DESCRIPTION
            A capture target describes something on screen, in physical pixels, with whatever each
            platform's ffmpeg capture source needs to find it again:

              Kind           Monitor, Window, Region or Synthetic
              Index          Position in the list it came from. For monitors, the number to pass to -Monitor
              Name           Something readable: the monitor's device name, or the window's title
              X, Y           Top left corner, on the virtual desktop (Windows, X11) or the screen (macOS)
              Width, Height  Size. Can be empty where the platform doesn't say, such as macOS screens
              Handle         Windows: the HMONITOR or HWND
              DeviceIndex    macOS: the AVFoundation device number
              Display        Linux: the X11 display, such as :0.0
              Monitor        Regions: the monitor target the region sits inside, if it fits inside one

            All coordinates are physical pixels, so on a scaled display a 4K monitor is 3840 wide, not 2560.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            New-CaptureTarget -Kind Region -X 100 -Y 100 -Width 800 -Height 600

            #### DESCRIPTION
            Describe an 800x600 area starting 100 pixels in from the top left.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only builds an object, nothing is changed')]
    PARAM(
        #What kind of target this is
        [Parameter(Mandatory)]
        [ValidateSet('Monitor','Window','Region','Synthetic')]
        [string]$Kind,
        #Position in the list it came from
        [Parameter()]
        [int]$Index = 0,
        #Readable name
        [Parameter()]
        [string]$Name,
        #Left edge, in physical pixels
        [Parameter()]
        [Nullable[int]]$X,
        #Top edge, in physical pixels
        [Parameter()]
        [Nullable[int]]$Y,
        #Width, in physical pixels
        [Parameter()]
        [Nullable[int]]$Width,
        #Height, in physical pixels
        [Parameter()]
        [Nullable[int]]$Height,
        #Windows HMONITOR or HWND
        [Parameter()]
        [long]$Handle,
        #macOS AVFoundation device number
        [Parameter()]
        [Nullable[int]]$DeviceIndex,
        #Linux X11 display, such as :0.0
        [Parameter()]
        [string]$Display,
        #Whether this is the primary monitor
        [Parameter()]
        [bool]$IsPrimary = $false,
        #Monitor DPI, where known. 96 is 100% scaling
        [Parameter()]
        [Nullable[int]]$Dpi,
        #Windows: the window's title
        [Parameter()]
        [string]$Title,
        #Windows: the window's process
        [Parameter()]
        [string]$ProcessName,
        #Windows: the window's process ID
        [Parameter()]
        [Nullable[int]]$ProcessId,
        #Windows: whether the window is minimized, so has nothing to capture
        [Parameter()]
        [bool]$IsMinimized = $false,
        #Regions: the monitor target the region fits inside
        [Parameter()]
        [PSCustomObject]$Monitor
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $platform = $(if($IsWindows){'Windows'}elseif($IsMacOS){'macOS'}else{'Linux'})
        $defaultDisplay = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]@('Kind','Index','Name','X','Y','Width','Height','IsPrimary'))
    }
    process{
        $target = [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.CaptureTarget'
            Kind = $Kind
            Index = $Index
            Name = $Name
            X = $X
            Y = $Y
            Width = $Width
            Height = $Height
            IsPrimary = $IsPrimary
            Dpi = $Dpi
            Scaling = $(if($Dpi){"$([math]::Round($Dpi / 96 * 100))%"})
            Handle = $Handle
            DeviceIndex = $DeviceIndex
            Display = $Display
            Title = $Title
            ProcessName = $ProcessName
            ProcessId = $ProcessId
            IsMinimized = $IsMinimized
            Monitor = $Monitor
            Platform = $platform
        }
        $target | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value ([System.Management.Automation.PSMemberInfo[]]@($defaultDisplay))
        $target
    }
}
