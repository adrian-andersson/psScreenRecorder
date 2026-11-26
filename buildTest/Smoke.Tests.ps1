<#
    Smoke test: the PUBLISHED module, used the way a person would, with a real ffmpeg.

    Module.Build.Tests.ps1 checks what the module exports. This checks the exported commands work once
    built and installed: the compiled .psm1, and the validator classes loaded through ScriptsToProcess.

    Skipped if ffmpeg can't be found. The Build Test workflow installs ffmpeg first, as psScreenRecorder
    never ships or installs it.

    To run it locally, build the module and put the build folder first on PSModulePath:
        Build-MFProject -Version 0.0.1
        $env:PSModulePath = "$(Resolve-Path ./build)$([IO.Path]::PathSeparator)$env:PSModulePath"
        Invoke-Pester ./buildTest
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeDiscovery {
    $ffmpegAvailable = [bool]([Environment]::GetEnvironmentVariable('PSSCREENRECORDER_FFMPEG') -or (Get-Command -Name 'ffmpeg' -CommandType Application -ErrorAction Ignore))
}

BeforeAll {
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $moduleName = (Import-Clixml -Path (Join-Path -Path $projectRoot -ChildPath 'moduleForgeConfig.xml')).moduleName
    $imported = Import-Module -Name $moduleName -Force -PassThru -ErrorAction Stop
    $savedCache = $env:PSSCREENRECORDER_CACHE
    $env:PSSCREENRECORDER_CACHE = Join-Path -Path $TestDrive -ChildPath 'cache'
}

AfterAll {
    $env:PSSCREENRECORDER_CACHE = $savedCache
    $imported | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Published module with a real ffmpeg' -Skip:(!$ffmpegAvailable) {
    BeforeAll {
        $installation = Find-FFmpeg
        $clip = Join-Path -Path $TestDrive -ChildPath 'smoke test.mp4'
        & $installation.FFmpegPath -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=30' -t 2 -c:v libx264 -pix_fmt yuv420p $clip
    }

    It 'Finds ffmpeg and ffprobe' {
        $installation.FFmpegPath | Should -Exist
        $installation.FFprobePath | Should -Exist
    }

    It 'Reads a video with Get-VideoMetadata' {
        $metadata = Get-VideoMetadata -Path $clip
        $metadata.Width | Should -Be 320
        $metadata.VideoCodec | Should -Be 'h264'
    }

    It 'Converts a video with ConvertTo-Gif, using the time parameters the validator class handles' {
        $gif = ConvertTo-Gif -Path $clip -Start 0.5 -End '0:01.5' -Fps 10
        $gif.Extension | Should -Be '.gif'
        (Get-VideoMetadata -Path $gif.FullName -CountFrames).FrameCount | Should -Be 10
    }

    It 'Converts through the version 1 alias' {
        $gif = convert-mp4togif -mp4Path $clip -gifPath (Join-Path -Path $TestDrive -ChildPath 'alias.gif')
        $gif.FullName | Should -Exist
    }
}
