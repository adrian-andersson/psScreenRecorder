function Select-ScreenRegion
{
    <#
        .SYNOPSIS
            Drag out an area of the screen to record

        .DESCRIPTION
            Dims every monitor and lets you drag out the area you want. The area shows through clear, with a red
            border and its size. Right-click, or press Esc, to cancel.

            Returns a capture target for the area, to pipe into Start-ScreenRecording, or nothing if cancelled.
            Start-ScreenRecording -SelectRegion does both in one step.

            The area is in physical pixels, measured by a window that is itself aware of each monitor's
            scaling, so it records exactly what was selected on scaled and mixed-scaling setups. Width and
            height are rounded down to even numbers, as most encoders need. A click without a drag is ignored.

              Windows  the overlay described above
              Linux    uses slop, if installed (sudo apt install slop), on X11
              macOS    not supported yet. Use Start-ScreenRecording -Rectangle

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Select-ScreenRegion | Start-ScreenRecording -Duration 30 -Wait

            #### DESCRIPTION
            Choose an area, then record it for 30 seconds.

        .EXAMPLE
            $area = Select-ScreenRegion
            1..3 | ForEach-Object { $area | Start-ScreenRecording -Duration 5 -Wait -Path ".\take$_.mp4" }

            #### DESCRIPTION
            Choose an area once, then record it three times.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM()
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
    }
    process{
        if($IsWindows)
        {
            $selection = Invoke-NativeRegionSelection
        }elseif($IsLinux){
            if(!(Get-Command -Name 'slop' -CommandType Application -ErrorAction Ignore))
            {
                throw 'Selecting an area on Linux needs slop, which is not installed. Install it (for example, sudo apt install slop), or use Start-ScreenRecording -Rectangle'
            }
            $selection = Invoke-SlopSelection
        }else{
            throw 'Selecting an area is not supported on macOS yet. Use Start-ScreenRecording -Rectangle x,y,width,height'
        }

        if(!$selection)
        {
            Write-Warning 'No area was selected'
            return
        }
        write-verbose "Selected: $($selection -join ',')"
        New-RegionTarget -X $selection[0] -Y $selection[1] -Width $selection[2] -Height $selection[3] -Monitors @(Get-CaptureTarget)
    }
}
