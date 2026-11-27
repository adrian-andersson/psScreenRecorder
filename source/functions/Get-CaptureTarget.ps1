function Get-CaptureTarget
{
    <#
        .SYNOPSIS
            List the monitors and windows Start-ScreenRecording can record

        .DESCRIPTION
            Returns capture targets: monitors by default, or windows with -Window, or the terminal this command
            is running in with -CurrentTerminal. Pipe one to Start-ScreenRecording to record it.

            Positions and sizes are physical pixels, the same pixels ffmpeg captures. On a monitor scaled to
            150%, a 4K monitor is reported as 3840x2160, not 2560x1440. The Scaling property shows each
            monitor's scaling on Windows.

            Monitors are listed on every platform:
              Windows  every monitor, with its bounds on the virtual desktop
              macOS    every screen AVFoundation can capture. Sizes aren't reported
              Linux    X11 monitors, from xrandr or xdpyinfo. Wayland isn't supported yet, as ffmpeg has no
                       released way to capture it

            -Window and -CurrentTerminal are Windows only for now. Windows are listed top of the z-order
            first. Minimized windows are listed, with IsMinimized set, but can't be recorded until restored.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-CaptureTarget

            #### DESCRIPTION
            List the monitors. Index is the number to give Start-ScreenRecording -Monitor.

        .EXAMPLE
            Get-CaptureTarget -Window '*Visual Studio Code*'

            #### DESCRIPTION
            List windows whose title or process name matches.

        .EXAMPLE
            Get-CaptureTarget -Window -Name 'msedge' | Select-Object -First 1 | Start-ScreenRecording -Duration 10 -Wait

            #### DESCRIPTION
            Record the top Edge window for ten seconds.
    #>

    [CmdletBinding(DefaultParameterSetName='Monitor')]
    [OutputType([PSCustomObject])]
    PARAM(
        #List monitors. This is the default
        [Parameter(ParameterSetName='Monitor')]
        [switch]$Monitor,
        #List windows (Windows only)
        [Parameter(Mandatory,ParameterSetName='Window')]
        [switch]$Window,
        #Only windows whose title or process name matches. Wildcards are allowed
        [Parameter(ParameterSetName='Window',Position=0)]
        [ArgumentCompleter({
            #Completers run outside the module, so run the private helper inside it. Dot-sourced, as in tests, there is no module
            $module = (Get-Command -Name $args[0] -ErrorAction Ignore).Module
            if($module){ & $module { Get-CaptureTargetCompletion -Kind Window -WordToComplete $args[0] } $args[2] }else{ Get-CaptureTargetCompletion -Kind Window -WordToComplete $args[2] }
        })]
        [SupportsWildcards()]
        [string]$Name,
        #The terminal window this command is running in (Windows only)
        [Parameter(Mandatory,ParameterSetName='CurrentTerminal')]
        [switch]$CurrentTerminal
    )
    begin{
        write-verbose "===========Executing $($MyInvocation.InvocationName)==========="
        Write-Debug "BoundParams: $($MyInvocation.BoundParameters|Out-String)"
        $windowsOnlyMessage = 'Recording a single window is only supported on Windows for now. Record a monitor, or a region with -Rectangle, instead'
    }
    process{
        switch($PSCmdlet.ParameterSetName)
        {
            'Monitor' {
                if($IsWindows)
                {
                    $index = 0
                    foreach($nativeMonitor in Get-NativeMonitorInfo)
                    {
                        $monitorSplat = @{
                            Kind = 'Monitor'
                            Index = $index
                            Name = $nativeMonitor.DeviceName
                            X = $nativeMonitor.Left
                            Y = $nativeMonitor.Top
                            Width = $nativeMonitor.Width
                            Height = $nativeMonitor.Height
                            IsPrimary = $nativeMonitor.IsPrimary
                            Dpi = $nativeMonitor.Dpi
                            Handle = $nativeMonitor.Handle
                        }
                        New-CaptureTarget @monitorSplat
                        $index++
                    }
                }elseif($IsMacOS){
                    write-verbose 'Asking AVFoundation for screens'
                    $listArguments = @('-hide_banner','-f','avfoundation','-list_devices','true','-i','')
                    $deviceList = Invoke-FFmpeg -ArgumentList $listArguments -IgnoreExitCode
                    ConvertFrom-AVFoundationDeviceList -DeviceListOutput $deviceList.StandardError
                }else{
                    $display = [Environment]::GetEnvironmentVariable('DISPLAY')
                    if(!$display)
                    {
                        if([Environment]::GetEnvironmentVariable('XDG_SESSION_TYPE') -eq 'wayland')
                        {
                            throw 'This is a Wayland session. ffmpeg has no released way to capture Wayland yet, so psScreenRecorder can only record X11 sessions on Linux'
                        }
                        throw 'There is no X11 display to record: DISPLAY is not set. On a headless machine, start a virtual display first, for example with xvfb-run'
                    }
                    if([Environment]::GetEnvironmentVariable('XDG_SESSION_TYPE') -eq 'wayland')
                    {
                        Write-Warning 'This is a Wayland session. Recording through XWayland only captures X11 apps, and Wayland windows may show as black'
                    }
                    $x11 = Get-X11MonitorOutput
                    ConvertFrom-XrandrMonitor -XrandrOutput $x11.Xrandr -XdpyinfoOutput $x11.Xdpyinfo -Display $display
                }
            }
            'Window' {
                if(!$IsWindows)
                {
                    throw $windowsOnlyMessage
                }
                $processNames = @{}
                $index = 0
                foreach($nativeWindow in Get-NativeWindowInfo)
                {
                    if(!$processNames.ContainsKey($nativeWindow.ProcessId))
                    {
                        $processNames[$nativeWindow.ProcessId] = (Get-Process -Id $nativeWindow.ProcessId -ErrorAction Ignore).ProcessName
                    }
                    $processName = $processNames[$nativeWindow.ProcessId]
                    if($Name -and !($nativeWindow.Title -like $Name -or $processName -like $Name))
                    {
                        continue
                    }
                    $windowSplat = @{
                        Kind = 'Window'
                        Index = $index
                        Name = $nativeWindow.Title
                        Title = $nativeWindow.Title
                        X = $nativeWindow.Left
                        Y = $nativeWindow.Top
                        Width = $nativeWindow.Width
                        Height = $nativeWindow.Height
                        Handle = $nativeWindow.Handle
                        ProcessId = $nativeWindow.ProcessId
                        ProcessName = $processName
                        IsMinimized = $nativeWindow.IsMinimized
                    }
                    New-CaptureTarget @windowSplat
                    $index++
                }
            }
            'CurrentTerminal' {
                if(!$IsWindows)
                {
                    throw $windowsOnlyMessage
                }
                $handle = Get-TerminalWindowHandle
                $nativeWindow = Get-NativeWindowInfo -Handle $handle
                if(!$nativeWindow)
                {
                    throw 'The terminal window could not be read'
                }
                $terminalSplat = @{
                    Kind = 'Window'
                    Name = $nativeWindow.Title
                    Title = $nativeWindow.Title
                    X = $nativeWindow.Left
                    Y = $nativeWindow.Top
                    Width = $nativeWindow.Width
                    Height = $nativeWindow.Height
                    Handle = $nativeWindow.Handle
                    ProcessId = $nativeWindow.ProcessId
                    ProcessName = (Get-Process -Id $nativeWindow.ProcessId -ErrorAction Ignore).ProcessName
                    IsMinimized = $nativeWindow.IsMinimized
                }
                New-CaptureTarget @terminalSplat
            }
        }
    }
}
