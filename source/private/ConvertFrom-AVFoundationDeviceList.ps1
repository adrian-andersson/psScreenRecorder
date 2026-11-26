function ConvertFrom-AVFoundationDeviceList
{
    <#
        .SYNOPSIS
            Read macOS screens from ffmpeg's AVFoundation device list

        .DESCRIPTION
            'ffmpeg -f avfoundation -list_devices true -i ""' prints the capture devices to stderr:
                [AVFoundation indev @ 0x7f8] AVFoundation video devices:
                [AVFoundation indev @ 0x7f8] [0] FaceTime HD Camera
                [AVFoundation indev @ 0x7f8] [1] Capture screen 0
                [AVFoundation indev @ 0x7f8] AVFoundation audio devices:
                [AVFoundation indev @ 0x7f8] [0] MacBook Pro Microphone

            Screens are the video devices named 'Capture screen N'. Cameras and audio devices are skipped.
            Returns a monitor capture target for each screen, with the device number ffmpeg needs. ffmpeg
            doesn't report screen sizes here, so Width and Height are left empty.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            $list = Invoke-FFmpeg -ArgumentList '-hide_banner','-f','avfoundation','-list_devices','true','-i','' -IgnoreExitCode
            ConvertFrom-AVFoundationDeviceList -DeviceListOutput $list.StandardError

            #### DESCRIPTION
            List the screens ffmpeg can capture on a Mac.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #Lines from ffmpeg's device list
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$DeviceListOutput
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        $inVideoSection = $false
        foreach($line in $DeviceListOutput)
        {
            if($line -match 'AVFoundation video devices:')
            {
                $inVideoSection = $true
                continue
            }
            if($line -match 'AVFoundation audio devices:')
            {
                $inVideoSection = $false
                continue
            }
            if($inVideoSection -and $line -match '\[(?<device>\d+)\]\s+Capture screen (?<screen>\d+)\s*$')
            {
                $targetSplat = @{
                    Kind = 'Monitor'
                    Index = [int]$Matches.screen
                    Name = "Capture screen $($Matches.screen)"
                    DeviceIndex = [int]$Matches.device
                    IsPrimary = ([int]$Matches.screen -eq 0)
                }
                New-CaptureTarget @targetSplat
            }
        }
    }
}
