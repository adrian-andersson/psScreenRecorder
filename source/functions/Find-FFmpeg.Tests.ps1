[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    #Walk up to the source folder, then map every source file by name, so tests don't care which subfolder a file is in
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'Invoke-FFmpeg.ps1'
        'Resolve-FFmpegExecutable.ps1'
        'Get-FFmpegCapability.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Find-FFmpeg'
    . $fileName

    #Empty files are enough, as Invoke-FFmpeg is mocked and never runs them
    $extension = $(if($IsWindows){'.exe'}else{''})
    $installFolder = Join-Path -Path $TestDrive -ChildPath 'ffmpeg install'
    $null = New-Item -ItemType Directory -Path $installFolder -Force
    $fakeFFmpeg = Join-Path -Path $installFolder -ChildPath "ffmpeg$extension"
    $fakeFFprobe = Join-Path -Path $installFolder -ChildPath "ffprobe$extension"
    $null = New-Item -ItemType File -Path $fakeFFmpeg,$fakeFFprobe -Force

    $loneFolder = Join-Path -Path $TestDrive -ChildPath 'ffmpeg only'
    $null = New-Item -ItemType Directory -Path $loneFolder -Force
    $loneFFmpeg = Join-Path -Path $loneFolder -ChildPath "ffmpeg$extension"
    $null = New-Item -ItemType File -Path $loneFFmpeg -Force
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Find-FFmpeg' {
    BeforeAll {
        $savedEnvironment = $env:PSSCREENRECORDER_FFMPEG
    }
    AfterAll {
        $env:PSSCREENRECORDER_FFMPEG = $savedEnvironment
    }
    BeforeEach {
        $script:psScreenRecorderFFmpeg = $null
        $env:PSSCREENRECORDER_FFMPEG = $null
        Mock Invoke-FFmpeg {
            [PSCustomObject]@{
                ExitCode = 0
                StandardOutput = @('ffmpeg version 9.1-full_build-www.gyan.dev Copyright (c) 2000-2026 the FFmpeg developers','built with gcc 16.2.0')
                StandardError = @()
            }
        }
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'ffmpeg','ffprobe' }
        #Several tests use a folder with no ffprobe on purpose
        Mock Write-Warning {}
    }

    Context 'Where it looks' {
        It 'Uses -Path when given a folder, and finds ffprobe next to ffmpeg' {
            $result = Find-FFmpeg -Path $installFolder
            $result.FFmpegPath | Should -Be $fakeFFmpeg
            $result.FFprobePath | Should -Be $fakeFFprobe
            $result.Source | Should -Be 'Parameter'
        }

        It 'Uses -Path when given the executable itself' {
            (Find-FFmpeg -Path $fakeFFmpeg).FFmpegPath | Should -Be $fakeFFmpeg
        }

        It 'Uses the PSSCREENRECORDER_FFMPEG environment variable when there is no -Path' {
            $env:PSSCREENRECORDER_FFMPEG = $installFolder
            $result = Find-FFmpeg
            $result.FFmpegPath | Should -Be $fakeFFmpeg
            $result.Source | Should -Be 'Environment'
        }

        It 'Prefers -Path over the environment variable' {
            $env:PSSCREENRECORDER_FFMPEG = $installFolder
            (Find-FFmpeg -Path $loneFolder).FFmpegPath | Should -Be $loneFFmpeg
        }

        It 'Uses PATH when nothing else is set' {
            Mock Get-Command { [PSCustomObject]@{ Source = $fakeFFmpeg } } -ParameterFilter { $Name -eq 'ffmpeg' }
            $result = Find-FFmpeg
            $result.FFmpegPath | Should -Be $fakeFFmpeg
            $result.Source | Should -Be 'Path'
        }

        It 'Falls back to ffprobe on PATH when it is not next to ffmpeg' {
            Mock Get-Command { [PSCustomObject]@{ Source = $fakeFFprobe } } -ParameterFilter { $Name -eq 'ffprobe' }
            (Find-FFmpeg -Path $loneFolder).FFprobePath | Should -Be $fakeFFprobe
        }

        It 'Warns, but still works, when there is no ffprobe anywhere' {
            $result = Find-FFmpeg -Path $loneFolder
            $result.FFprobePath | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like '*ffprobe was not found*' }
        }
    }

    Context 'When it fails' {
        It 'Throws with install advice, and says it does not install ffmpeg, when nothing is found' {
            { Find-FFmpeg } | Should -Throw '*does not install ffmpeg*Install it with:*'
        }

        It 'Throws when -Path does not exist' {
            { Find-FFmpeg -Path (Join-Path -Path $TestDrive -ChildPath 'missing') } | Should -Throw '*ffmpeg was not found at*'
        }

        It 'Throws when the environment variable points nowhere' {
            $env:PSSCREENRECORDER_FFMPEG = Join-Path -Path $TestDrive -ChildPath 'missing'
            { Find-FFmpeg } | Should -Throw '*PSSCREENRECORDER_FFMPEG*'
        }

        It 'Throws when the file does not run' {
            Mock Invoke-FFmpeg { throw 'not a program' }
            { Find-FFmpeg -Path $fakeFFmpeg } | Should -Throw '*did not run as ffmpeg*'
        }

        It 'Throws when the file runs but is not ffmpeg' {
            Mock Invoke-FFmpeg { [PSCustomObject]@{ ExitCode = 0; StandardOutput = @('Something else 1.0'); StandardError = @() } }
            { Find-FFmpeg -Path $fakeFFmpeg } | Should -Throw '*does not look like ffmpeg*'
        }
    }

    Context 'Version numbers' {
        It 'Reads <VersionLine> as <Expected>' -ForEach @(
            @{ VersionLine = 'ffmpeg version 9.1-full_build-www.gyan.dev Copyright'; Text = '9.1-full_build-www.gyan.dev'; Expected = '9.1.0' }
            @{ VersionLine = 'ffmpeg version 6.1.1-3ubuntu5 Copyright'; Text = '6.1.1-3ubuntu5'; Expected = '6.1.1' }
            @{ VersionLine = 'ffmpeg version n7.1 Copyright'; Text = 'n7.1'; Expected = '7.1.0' }
            @{ VersionLine = 'ffmpeg version 7.1.1 Copyright'; Text = '7.1.1'; Expected = '7.1.1' }
        ) {
            Mock Invoke-FFmpeg { [PSCustomObject]@{ ExitCode = 0; StandardOutput = @($VersionLine); StandardError = @() } }
            $result = Find-FFmpeg -Path $fakeFFmpeg
            $result.Version | Should -Be $Text
            $result.VersionNumber | Should -Be ([version]$Expected)
        }

        It 'Has no version number for a build from git' {
            Mock Invoke-FFmpeg { [PSCustomObject]@{ ExitCode = 0; StandardOutput = @('ffmpeg version N-113000-g1234abcd Copyright'); StandardError = @() } }
            $result = Find-FFmpeg -Path $fakeFFmpeg
            $result.Version | Should -Be 'N-113000-g1234abcd'
            $result.VersionNumber | Should -BeNullOrEmpty
        }
    }

    Context 'Caching' {
        It 'Only checks ffmpeg once per session' {
            $null = Find-FFmpeg -Path $installFolder
            $null = Find-FFmpeg
            $null = Find-FFmpeg
            Should -Invoke Invoke-FFmpeg -Times 1 -Exactly
        }

        It 'Uses what -Path found for later calls' {
            $null = Find-FFmpeg -Path $loneFolder
            (Find-FFmpeg).FFmpegPath | Should -Be $loneFFmpeg
        }

        It 'Looks again with -Refresh' {
            $env:PSSCREENRECORDER_FFMPEG = $installFolder
            $null = Find-FFmpeg
            $null = Find-FFmpeg -Refresh
            Should -Invoke Invoke-FFmpeg -Times 2 -Exactly
        }
    }

    Context 'Capabilities' {
        It 'Adds capture sources and working encoders with -IncludeCapability' {
            Mock Get-FFmpegCapability {
                [PSCustomObject]@{ CaptureSources = @('x11grab'); WorkingEncoders = @('libx264','libx265'); CheckedAt = [datetime]::UtcNow }
            }
            $result = Find-FFmpeg -Path $installFolder -IncludeCapability
            $result.CaptureSources | Should -Be @('x11grab')
            $result.Encoders | Should -Be @('libx264','libx265')
            $result.CapabilityCheckedAt | Should -Not -BeNullOrEmpty
            Should -Invoke Get-FFmpegCapability -ParameterFilter { $FFmpegPath -eq $fakeFFmpeg -and $Version -eq '9.1-full_build-www.gyan.dev' }
        }

        It 'Does not check capabilities unless asked' {
            Mock Get-FFmpegCapability {}
            $result = Find-FFmpeg -Path $installFolder
            Should -Invoke Get-FFmpegCapability -Times 0 -Exactly
            $result.PSObject.Properties.Name | Should -Not -Contain 'Encoders'
        }

        It 'Passes -Refresh on to the capability check' {
            Mock Get-FFmpegCapability { [PSCustomObject]@{ CaptureSources = @(); WorkingEncoders = @(); CheckedAt = [datetime]::UtcNow } }
            $null = Find-FFmpeg -Path $installFolder -IncludeCapability -Refresh
            Should -Invoke Get-FFmpegCapability -ParameterFilter { $Refresh }
        }
    }
}
