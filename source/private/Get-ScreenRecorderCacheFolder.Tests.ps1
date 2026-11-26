[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-ScreenRecorderCacheFolder'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Get-ScreenRecorderCacheFolder' {
    BeforeAll {
        $savedCache = $env:PSSCREENRECORDER_CACHE
        $savedXdg = $env:XDG_CACHE_HOME
    }
    AfterEach {
        $env:PSSCREENRECORDER_CACHE = $savedCache
        $env:XDG_CACHE_HOME = $savedXdg
    }

    It 'Uses PSSCREENRECORDER_CACHE when it is set' {
        $env:PSSCREENRECORDER_CACHE = Join-Path -Path $TestDrive -ChildPath 'my cache'
        Get-ScreenRecorderCacheFolder | Should -Be (Join-Path -Path $TestDrive -ChildPath 'my cache')
    }

    It 'Uses the local, not roaming, app data folder on Windows' -Skip:(-not $IsWindows) {
        $env:PSSCREENRECORDER_CACHE = $null
        Get-ScreenRecorderCacheFolder | Should -Be (Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'psScreenRecorder')
    }

    It 'Uses ~/Library/Caches on macOS' -Skip:(-not $IsMacOS) {
        $env:PSSCREENRECORDER_CACHE = $null
        Get-ScreenRecorderCacheFolder | Should -Be (Join-Path -Path $HOME -ChildPath 'Library/Caches/psScreenRecorder')
    }

    It 'Uses XDG_CACHE_HOME on Linux when it is set' -Skip:(-not $IsLinux) {
        $env:PSSCREENRECORDER_CACHE = $null
        $env:XDG_CACHE_HOME = '/tmp/xdg'
        Get-ScreenRecorderCacheFolder | Should -Be '/tmp/xdg/psScreenRecorder'
    }

    It 'Uses ~/.cache on Linux when XDG_CACHE_HOME is not set' -Skip:(-not $IsLinux) {
        $env:PSSCREENRECORDER_CACHE = $null
        $env:XDG_CACHE_HOME = $null
        Get-ScreenRecorderCacheFolder | Should -Be (Join-Path -Path $HOME -ChildPath '.cache/psScreenRecorder')
    }
}
