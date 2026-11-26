function Get-CaptureInputArgument
{
    <#
        .SYNOPSIS
            Build the ffmpeg input arguments, and any filters they need, to capture a target with a backend

        .DESCRIPTION
            Turns a capture target into what ffmpeg needs, for one capture source:

              synthetic     -re -f lavfi -i testsrc2=size=WxH:rate=N  (a moving test pattern, in real time)
              gfxcapture    -f lavfi -i gfxcapture=hmonitor=...|hwnd=...  with crop_* for a region
              ddagrab       -f lavfi -i ddagrab=output_idx=...  with offset_x/y and video_size for a region
              gdigrab       -f gdigrab ... -offset_x -offset_y -video_size -i desktop
              avfoundation  -f avfoundation ... -i "<device>:none"  then a crop filter for a region
              x11grab       -f x11grab ... -video_size WxH -i "<display>+X,Y"

            gfxcapture and ddagrab hand over frames in GPU memory, so they get 'hwdownload,format=bgra' to
            bring them back for encoding.

            Returns the backend, the input arguments, and the filters to start the filter chain with.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-CaptureInputArgument -Target (Get-CaptureTarget | Select-Object -First 1) -Backend gfxcapture -Fps 30

            #### DESCRIPTION
            Arguments to record the first monitor with Windows.Graphics.Capture at 30 frames per second.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    PARAM(
        #The capture target
        [Parameter(Mandatory)]
        [PSCustomObject]$Target,
        #The capture source, from Select-CaptureBackend
        [Parameter(Mandatory)]
        [ValidateSet('gfxcapture','ddagrab','gdigrab','avfoundation','x11grab','synthetic')]
        [string]$Backend,
        #Frames per second
        [Parameter()]
        [ValidateRange(1,240)]
        [int]$Fps = 30,
        #Whether to record the mouse pointer
        [Parameter()]
        [bool]$ShowCursor = $true
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        $cursor = $(if($ShowCursor){'1'}else{'0'})
    }
    process{
        $kind = $Target.Kind
        $inputArguments = [System.Collections.Generic.List[string]]::new()
        $filters = [System.Collections.Generic.List[string]]::new()

        #Where a region sits inside its monitor
        if($kind -eq 'Region' -and $Target.Monitor)
        {
            $monitorX = [int]$Target.Monitor.X
            $monitorY = [int]$Target.Monitor.Y
            $offsetX = $Target.X - $monitorX
            $offsetY = $Target.Y - $monitorY
        }

        switch($Backend)
        {
            'synthetic' {
                $inputArguments.AddRange([string[]]@('-re','-f','lavfi','-i',"testsrc2=size=$($Target.Width)x$($Target.Height):rate=$Fps"))
            }
            'gfxcapture' {
                $source = switch($kind)
                {
                    'Window' { "gfxcapture=hwnd=$($Target.Handle)" }
                    'Monitor' { "gfxcapture=hmonitor=$($Target.Handle)" }
                    'Region' {
                        $monitorWidth = [int]$Target.Monitor.Width
                        $monitorHeight = [int]$Target.Monitor.Height
                        $cropRight = $monitorWidth - $offsetX - $Target.Width
                        $cropBottom = $monitorHeight - $offsetY - $Target.Height
                        "gfxcapture=hmonitor=$($Target.Monitor.Handle):crop_left=$($offsetX):crop_top=$($offsetY):crop_right=$($cropRight):crop_bottom=$($cropBottom)"
                    }
                    default { throw "gfxcapture can't record a $kind target" }
                }
                $inputArguments.AddRange([string[]]@('-f','lavfi','-i',"$($source):capture_cursor=$($cursor):max_framerate=$Fps"))
                $filters.AddRange([string[]]@('hwdownload','format=bgra'))
            }
            'ddagrab' {
                $monitorTarget = $(if($kind -eq 'Region'){$Target.Monitor}else{$Target})
                $source = "ddagrab=output_idx=$($monitorTarget.Index):framerate=$($Fps):draw_mouse=$cursor"
                if($kind -eq 'Region')
                {
                    $source = "$($source):offset_x=$($offsetX):offset_y=$($offsetY):video_size=$($Target.Width)x$($Target.Height)"
                }elseif($kind -ne 'Monitor'){
                    throw "ddagrab can't record a $kind target"
                }
                $inputArguments.AddRange([string[]]@('-f','lavfi','-i',$source))
                $filters.AddRange([string[]]@('hwdownload','format=bgra'))
            }
            'gdigrab' {
                $inputArguments.AddRange([string[]]@(
                    '-f','gdigrab','-framerate',[string]$Fps,'-draw_mouse',$cursor,'-show_region','0'
                    '-offset_x',[string]$Target.X,'-offset_y',[string]$Target.Y,'-video_size',"$($Target.Width)x$($Target.Height)"
                    '-i','desktop'
                ))
            }
            'avfoundation' {
                $screen = $(if($kind -eq 'Region'){$Target.Monitor}else{$Target})
                if($null -eq $screen.DeviceIndex)
                {
                    throw 'The macOS screen to record is not known. Use a target from Get-CaptureTarget'
                }
                $inputArguments.AddRange([string[]]@('-f','avfoundation','-framerate',[string]$Fps,'-capture_cursor',$cursor,'-i',"$($screen.DeviceIndex):none"))
                if($kind -eq 'Region')
                {
                    $filters.Add("crop=$($Target.Width):$($Target.Height):$($offsetX):$($offsetY)")
                }
            }
            'x11grab' {
                $display = $(if($Target.Display){$Target.Display}elseif($Target.Monitor.Display){$Target.Monitor.Display}else{[Environment]::GetEnvironmentVariable('DISPLAY')})
                if(!$display)
                {
                    throw 'There is no X11 display to record: DISPLAY is not set'
                }
                $inputArguments.AddRange([string[]]@('-f','x11grab','-framerate',[string]$Fps,'-draw_mouse',$cursor))
                if($Target.Width -and $Target.Height)
                {
                    $inputArguments.AddRange([string[]]@('-video_size',"$($Target.Width)x$($Target.Height)"))
                }
                $inputArguments.AddRange([string[]]@('-i',"$($display)+$([int]$Target.X),$([int]$Target.Y)"))
            }
        }

        [PSCustomObject]@{
            PSTypeName = 'psScreenRecorder.CaptureInput'
            Backend = $Backend
            InputArguments = $inputArguments.ToArray()
            Filters = $filters.ToArray()
        }
    }
}
