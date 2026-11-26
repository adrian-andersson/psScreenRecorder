[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'New-CaptureTarget.ps1'
        'Get-NativeMonitorInfo.ps1'
        'Get-NativeWindowInfo.ps1'
        'Get-TerminalWindowHandle.ps1'
        'Invoke-FFmpeg.ps1'
        'ConvertFrom-AVFoundationDeviceList.ps1'
        'ConvertFrom-XrandrMonitor.ps1'
        'Get-X11MonitorOutput.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-CaptureTarget'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Get-CaptureTarget' {
    Context 'Windows' -Skip:(!$IsWindows) {
        BeforeEach {
            #A 150% scaled 4K primary, and a 1080p monitor to its left
            Mock Get-NativeMonitorInfo {
                [PSCustomObject]@{ Handle = 65537; DeviceName = '\\.\DISPLAY1'; Left = 0; Top = 0; Width = 3840; Height = 2160; IsPrimary = $true; Dpi = 144 }
                [PSCustomObject]@{ Handle = 65539; DeviceName = '\\.\DISPLAY2'; Left = -1920; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false; Dpi = 96 }
            }
            Mock Get-NativeWindowInfo -ParameterFilter { !$PSBoundParameters.ContainsKey('Handle') } {
                [PSCustomObject]@{ Handle = 11; Title = 'Notes - Notepad'; ProcessId = $PID; Left = 10; Top = 20; Width = 800; Height = 600; IsMinimized = $false }
                [PSCustomObject]@{ Handle = 12; Title = 'Inbox - Mail'; ProcessId = $PID; Left = 0; Top = 0; Width = 1200; Height = 900; IsMinimized = $true }
            }
        }

        It 'Lists monitors in physical pixels, numbered from 0, with their scaling' {
            $monitors = @(Get-CaptureTarget)
            $monitors.Count | Should -Be 2
            $monitors[0].Index | Should -Be 0
            $monitors[0].Width | Should -Be 3840
            $monitors[0].Scaling | Should -Be '150%'
            $monitors[0].Handle | Should -Be 65537
            $monitors[1].X | Should -Be -1920
            $monitors[1].IsPrimary | Should -BeFalse
        }

        It 'Lists windows, with their process, top first' {
            $windows = @(Get-CaptureTarget -Window)
            $windows.Count | Should -Be 2
            $windows[0].Kind | Should -Be 'Window'
            $windows[0].Title | Should -Be 'Notes - Notepad'
            $windows[0].ProcessName | Should -Be (Get-Process -Id $PID).ProcessName
            $windows[1].IsMinimized | Should -BeTrue
        }

        It 'Filters windows by title or process name' {
            (Get-CaptureTarget -Window '*Notepad*').Title | Should -Be 'Notes - Notepad'
            @(Get-CaptureTarget -Window -Name (Get-Process -Id $PID).ProcessName).Count | Should -Be 2
            Get-CaptureTarget -Window '*nothing like this*' | Should -BeNullOrEmpty
        }

        It 'Finds the current terminal''s window' {
            Mock Get-TerminalWindowHandle { 99 }
            Mock Get-NativeWindowInfo -ParameterFilter { $Handle -eq 99 } { [PSCustomObject]@{ Handle = 99; Title = 'Terminal'; ProcessId = $PID; Left = 0; Top = 0; Width = 1000; Height = 700; IsMinimized = $false } }
            $terminal = Get-CaptureTarget -CurrentTerminal
            $terminal.Kind | Should -Be 'Window'
            $terminal.Handle | Should -Be 99
        }

        It 'Throws when the terminal window can''t be read' {
            Mock Get-TerminalWindowHandle { 99 }
            Mock Get-NativeWindowInfo -ParameterFilter { $Handle -eq 99 } {}
            { Get-CaptureTarget -CurrentTerminal } | Should -Throw '*could not be read*'
        }
    }

    Context 'Not Windows' -Skip:$IsWindows {
        It 'Throws for <Switch>, which is Windows only for now' -ForEach @(
            @{ Switch = 'Window' }
            @{ Switch = 'CurrentTerminal' }
        ) {
            $splat = @{ $Switch = $true }
            { Get-CaptureTarget @splat } | Should -Throw '*only supported on Windows*'
        }
    }

    Context 'macOS' -Skip:(!$IsMacOS) {
        It 'Lists the screens AVFoundation can capture' {
            Mock Invoke-FFmpeg { [PSCustomObject]@{ ExitCode = 1; StandardOutput = @(); StandardError = @('[AVFoundation indev @ 0x1] AVFoundation video devices:','[AVFoundation indev @ 0x1] [2] Capture screen 0') } }
            $screen = Get-CaptureTarget
            $screen.DeviceIndex | Should -Be 2
            Should -Invoke Invoke-FFmpeg -ParameterFilter { $IgnoreExitCode -and $ArgumentList -contains '-list_devices' }
        }
    }

    Context 'Linux' -Skip:(!$IsLinux) {
        BeforeAll {
            $savedDisplay = $env:DISPLAY
            $savedSession = $env:XDG_SESSION_TYPE
        }
        AfterEach {
            $env:DISPLAY = $savedDisplay
            $env:XDG_SESSION_TYPE = $savedSession
        }

        It 'Lists X11 monitors on DISPLAY' {
            $env:DISPLAY = ':5'
            $env:XDG_SESSION_TYPE = 'x11'
            Mock Get-X11MonitorOutput { [PSCustomObject]@{ Xrandr = @(' 0: +*HDMI-1 1920/527x1080/296+0+0  HDMI-1'); Xdpyinfo = @() } }
            $monitor = Get-CaptureTarget
            $monitor.Width | Should -Be 1920
            $monitor.Display | Should -Be ':5'
        }

        It 'Throws, explaining why, on Wayland with no X11 display' {
            $env:DISPLAY = $null
            $env:XDG_SESSION_TYPE = 'wayland'
            { Get-CaptureTarget } | Should -Throw '*Wayland*'
        }

        It 'Throws, suggesting a virtual display, with no DISPLAY' {
            $env:DISPLAY = $null
            $env:XDG_SESSION_TYPE = $null
            { Get-CaptureTarget } | Should -Throw '*xvfb-run*'
        }

        It 'Warns that XWayland only captures X11 apps' {
            $env:DISPLAY = ':0'
            $env:XDG_SESSION_TYPE = 'wayland'
            Mock Write-Warning {}
            Mock Get-X11MonitorOutput { [PSCustomObject]@{ Xrandr = @(); Xdpyinfo = @() } }
            $null = Get-CaptureTarget
            Should -Invoke Write-Warning -ParameterFilter { $Message -like '*XWayland*' }
        }
    }
}

Describe 'Get-X11MonitorOutput' {
    It 'Returns empty output when neither xrandr nor xdpyinfo is installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'xrandr','xdpyinfo' }
        $output = Get-X11MonitorOutput
        $output.Xrandr | Should -BeNullOrEmpty
        $output.Xdpyinfo | Should -BeNullOrEmpty
    }
}
