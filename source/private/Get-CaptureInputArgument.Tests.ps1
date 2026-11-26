[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    foreach($dependency in @('New-CaptureTarget.ps1'))
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-CaptureInputArgument'
    . $fileName

    #A second monitor to the right of a 1920 wide primary, so offsets are relative to it, not the desktop
    $monitor = New-CaptureTarget -Kind Monitor -Index 1 -X 1920 -Y 0 -Width 2560 -Height 1440 -Handle 65539
    $region = New-CaptureTarget -Kind Region -X 2020 -Y 50 -Width 800 -Height 600 -Monitor $monitor
    $window = New-CaptureTarget -Kind Window -X 100 -Y 200 -Width 1000 -Height 700 -Handle 4242
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Get-CaptureInputArgument' {
    Context 'synthetic' {
        It 'Generates a test pattern at the target size and frame rate, in real time' {
            $result = Get-CaptureInputArgument -Target (New-CaptureTarget -Kind Synthetic -Width 640 -Height 360) -Backend synthetic -Fps 25
            $result.InputArguments | Should -Be @('-re','-f','lavfi','-i','testsrc2=size=640x360:rate=25')
            $result.Filters | Should -BeNullOrEmpty
        }
    }

    Context 'gfxcapture' {
        It 'Finds a monitor by its handle' {
            $result = Get-CaptureInputArgument -Target $monitor -Backend gfxcapture -Fps 30
            $result.InputArguments | Should -Be @('-f','lavfi','-i','gfxcapture=hmonitor=65539:capture_cursor=1:max_framerate=30')
        }

        It 'Finds a window by its handle' {
            $result = Get-CaptureInputArgument -Target $window -Backend gfxcapture
            $result.InputArguments[-1] | Should -BeLike 'gfxcapture=hwnd=4242:*'
        }

        It 'Crops a region from its monitor, measured from the monitor''s edges' {
            $result = Get-CaptureInputArgument -Target $region -Backend gfxcapture
            #Left: 2020-1920. Top: 50. Right: 2560-100-800. Bottom: 1440-50-600
            $result.InputArguments[-1] | Should -BeLike 'gfxcapture=hmonitor=65539:crop_left=100:crop_top=50:crop_right=1660:crop_bottom=790:*'
        }

        It 'Brings frames back from the GPU' {
            (Get-CaptureInputArgument -Target $monitor -Backend gfxcapture).Filters | Should -Be @('hwdownload','format=bgra')
        }

        It 'Leaves the cursor out when asked' {
            (Get-CaptureInputArgument -Target $monitor -Backend gfxcapture -ShowCursor $false).InputArguments[-1] | Should -BeLike '*capture_cursor=0*'
        }
    }

    Context 'ddagrab' {
        It 'Uses the monitor''s index as the output' {
            (Get-CaptureInputArgument -Target $monitor -Backend ddagrab -Fps 60).InputArguments[-1] | Should -Be 'ddagrab=output_idx=1:framerate=60:draw_mouse=1'
        }

        It 'Offsets a region from its monitor''s corner' {
            (Get-CaptureInputArgument -Target $region -Backend ddagrab).InputArguments[-1] | Should -BeLike '*:offset_x=100:offset_y=50:video_size=800x600'
        }

        It 'Throws for a window' {
            { Get-CaptureInputArgument -Target $window -Backend ddagrab } | Should -Throw '*Window*'
        }
    }

    Context 'gdigrab' {
        It 'Uses desktop coordinates, so works across monitors' {
            $arguments = (Get-CaptureInputArgument -Target $region -Backend gdigrab -Fps 15).InputArguments
            $arguments -join ' ' | Should -Be '-f gdigrab -framerate 15 -draw_mouse 1 -show_region 0 -offset_x 2020 -offset_y 50 -video_size 800x600 -i desktop'
        }

        It 'Records a window by its area of the screen' {
            ((Get-CaptureInputArgument -Target $window -Backend gdigrab).InputArguments -join ' ') | Should -BeLike '*-offset_x 100 -offset_y 200 -video_size 1000x700*'
        }
    }

    Context 'avfoundation' {
        BeforeAll {
            $screen = New-CaptureTarget -Kind Monitor -DeviceIndex 3
        }

        It 'Opens the screen''s device, with no audio' {
            $arguments = (Get-CaptureInputArgument -Target $screen -Backend avfoundation -Fps 30).InputArguments
            $arguments -join ' ' | Should -Be '-f avfoundation -framerate 30 -capture_cursor 1 -i 3:none'
        }

        It 'Crops a region with a filter' {
            $screenRegion = New-CaptureTarget -Kind Region -X 10 -Y 20 -Width 300 -Height 200 -Monitor $screen
            $result = Get-CaptureInputArgument -Target $screenRegion -Backend avfoundation
            $result.InputArguments[-1] | Should -Be '3:none'
            $result.Filters | Should -Be @('crop=300:200:10:20')
        }

        It 'Throws without a device number' {
            { Get-CaptureInputArgument -Target (New-CaptureTarget -Kind Monitor) -Backend avfoundation } | Should -Throw '*not known*'
        }
    }

    Context 'x11grab' {
        It 'Captures from the display, at the target''s position and size' {
            $x11Monitor = New-CaptureTarget -Kind Monitor -X 1920 -Y 0 -Width 1280 -Height 1024 -Display ':0'
            ((Get-CaptureInputArgument -Target $x11Monitor -Backend x11grab -Fps 30).InputArguments -join ' ') | Should -Be '-f x11grab -framerate 30 -draw_mouse 1 -video_size 1280x1024 -i :0+1920,0'
        }

        It 'Uses the region''s monitor''s display' {
            $x11Monitor = New-CaptureTarget -Kind Monitor -X 0 -Y 0 -Width 1280 -Height 1024 -Display ':99'
            $x11Region = New-CaptureTarget -Kind Region -X 5 -Y 6 -Width 100 -Height 50 -Monitor $x11Monitor
            (Get-CaptureInputArgument -Target $x11Region -Backend x11grab).InputArguments[-1] | Should -Be ':99+5,6'
        }

        It 'Leaves the size out when it is not known, to capture the whole screen' {
            $x11Screen = New-CaptureTarget -Kind Monitor -X 0 -Y 0 -Display ':0'
            (Get-CaptureInputArgument -Target $x11Screen -Backend x11grab).InputArguments | Should -Not -Contain '-video_size'
        }

        It 'Falls back to DISPLAY, and throws without one' {
            $savedDisplay = $env:DISPLAY
            try{
                $env:DISPLAY = ':7'
                (Get-CaptureInputArgument -Target (New-CaptureTarget -Kind Monitor -X 0 -Y 0) -Backend x11grab).InputArguments[-1] | Should -Be ':7+0,0'
                $env:DISPLAY = $null
                { Get-CaptureInputArgument -Target (New-CaptureTarget -Kind Monitor -X 0 -Y 0) -Backend x11grab } | Should -Throw '*DISPLAY*'
            }finally{
                $env:DISPLAY = $savedDisplay
            }
        }
    }
}
