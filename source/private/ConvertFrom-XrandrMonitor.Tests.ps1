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
    $functionName = 'ConvertFrom-XrandrMonitor'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-XrandrMonitor' {
    It 'Reads each monitor from xrandr --listmonitors' {
        $xrandr = @(
            'Monitors: 2'
            ' 0: +*DP-1 2560/597x1440/336+0+0  DP-1'
            ' 1: +HDMI-1 1920/527x1080/296+2560+180  HDMI-1'
        )
        $monitors = @(ConvertFrom-XrandrMonitor -XrandrOutput $xrandr -Display ':0')
        $monitors.Count | Should -Be 2
        $monitors[0].Name | Should -Be 'DP-1'
        $monitors[0].IsPrimary | Should -BeTrue
        $monitors[0].Width | Should -Be 2560
        $monitors[0].Height | Should -Be 1440
        $monitors[1].X | Should -Be 2560
        $monitors[1].Y | Should -Be 180
        $monitors[1].IsPrimary | Should -BeFalse
        $monitors[1].Display | Should -Be ':0'
        $monitors[1].Kind | Should -Be 'Monitor'
    }

    It 'Reads monitors placed left of or above the origin' {
        $monitor = ConvertFrom-XrandrMonitor -XrandrOutput ' 0: +eDP-1 1920/344x1080/194+-1920+-200  eDP-1' -Display ':1'
        $monitor.X | Should -Be -1920
        $monitor.Y | Should -Be -200
    }

    It 'Falls back to the screen size from xdpyinfo, as on Xvfb' {
        $xdpyinfo = @('name of display:    :99','screen #0:','  dimensions:    1280x1024 pixels (338x270 millimeters)')
        $monitor = ConvertFrom-XrandrMonitor -XrandrOutput @() -XdpyinfoOutput $xdpyinfo -Display ':99'
        $monitor.Width | Should -Be 1280
        $monitor.Height | Should -Be 1024
        $monitor.IsPrimary | Should -BeTrue
        $monitor.Display | Should -Be ':99'
    }

    It 'Returns the whole screen, with no size, when neither tool said anything' {
        $monitor = ConvertFrom-XrandrMonitor -XrandrOutput @() -XdpyinfoOutput @() -Display ':0'
        $monitor.Width | Should -BeNullOrEmpty
        $monitor.X | Should -Be 0
    }
}
