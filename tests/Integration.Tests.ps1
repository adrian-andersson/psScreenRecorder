<#
    Integration tests: the real thing, end to end, with a real ffmpeg.

    Unit tests next to each function mock Invoke-FFmpeg, so they run anywhere. These don't: they make
    short clips with ffmpeg's own test pattern (testsrc2), run them through the commands, and check the
    results with ffprobe. There is no screen involved, so they run on headless CI runners too.

    If ffmpeg can't be found (PSSCREENRECORDER_FFMPEG, then PATH), every test here is skipped, with the
    reason shown, rather than failing. CI installs ffmpeg so they run on pull requests.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeDiscovery {
    $ffmpegAvailable = [bool]([Environment]::GetEnvironmentVariable('PSSCREENRECORDER_FFMPEG') -or (Get-Command -Name 'ffmpeg' -CommandType Application -ErrorAction Ignore))
    if(!$ffmpegAvailable)
    {
        Write-Warning 'ffmpeg was not found, so the integration tests will be skipped. Install ffmpeg, or set PSSCREENRECORDER_FFMPEG, to run them'
    }
}

BeforeAll {
    #Load the whole module from source. Classes first, as functions use them in their parameters
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $sourcePath = Join-Path -Path $projectRoot -ChildPath 'source'
    $loadOrder = @('enums','classes','validationClasses','private','functions')
    foreach($folder in $loadOrder)
    {
        $folderPath = Join-Path -Path $sourcePath -ChildPath $folder
        if(Test-Path -LiteralPath $folderPath)
        {
            Get-ChildItem -LiteralPath $folderPath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object { . $_.FullName }
        }
    }

    #Keep the capability cache out of the real one
    $savedCache = $env:PSSCREENRECORDER_CACHE
    $env:PSSCREENRECORDER_CACHE = Join-Path -Path $TestDrive -ChildPath 'cache'

    $clipFolder = Join-Path -Path $TestDrive -ChildPath 'clips with spaces'
    $null = New-Item -ItemType Directory -Path $clipFolder -Force
}

AfterAll {
    $env:PSSCREENRECORDER_CACHE = $savedCache
}

Describe 'Integration with a real ffmpeg' -Skip:(!$ffmpegAvailable) {
    BeforeAll {
        $installation = Find-FFmpeg -Refresh

        #4 seconds of moving test pattern, 640x360 at 30 fps
        $movingClip = Join-Path -Path $clipFolder -ChildPath 'moving clip.mp4'
        $null = Invoke-FFmpeg -ArgumentList @(
            '-hide_banner','-loglevel','error','-y'
            '-f','lavfi','-i','testsrc2=size=640x360:rate=30','-t','4'
            '-c:v','libx264','-pix_fmt','yuv420p',$movingClip
        )

        #1 second of movement, then the last frame held for 3 seconds: like a terminal waiting for input
        $pausedClip = Join-Path -Path $clipFolder -ChildPath 'paused.mp4'
        $null = Invoke-FFmpeg -ArgumentList @(
            '-hide_banner','-loglevel','error','-y'
            '-f','lavfi','-i','testsrc2=size=320x180:rate=30,trim=0:1,tpad=stop_mode=clone:stop_duration=3'
            '-c:v','libx264','-pix_fmt','yuv420p',$pausedClip
        )
    }

    Context 'Find-FFmpeg' {
        It 'Finds a working ffmpeg and ffprobe' {
            $installation.FFmpegPath | Should -Exist
            $installation.FFprobePath | Should -Exist
            $installation.Version | Should -Not -BeNullOrEmpty
        }

        It 'Finds at least one working H.264 encoder' {
            $capability = Find-FFmpeg -IncludeCapability
            @($capability.Encoders).Where{ $_ -like 'libx264*' -or $_ -like 'h264_*' }.Count | Should -BeGreaterThan 0
        }

        It 'Reuses the saved capabilities in a new session' {
            $null = Find-FFmpeg -IncludeCapability
            $script:psScreenRecorderCapability = @{}
            (Get-FFmpegCapability -FFmpegPath $installation.FFmpegPath -Version $installation.Version).FromCache | Should -BeTrue
        }
    }

    Context 'Get-VideoMetadata' {
        It 'Reads the size, frame rate, duration and codec of a clip' {
            $result = Get-VideoMetadata -Path $movingClip
            $result.Width | Should -Be 640
            $result.Height | Should -Be 360
            $result.FrameRate | Should -Be 30
            $result.Duration.TotalSeconds | Should -BeGreaterOrEqual 3.9
            $result.Duration.TotalSeconds | Should -BeLessOrEqual 4.1
            $result.VideoCodec | Should -Be 'h264'
            $result.HasAudio | Should -BeFalse
        }

        It 'Counts frames with -CountFrames' {
            (Get-VideoMetadata -Path $movingClip -CountFrames).FrameCount | Should -Be 120
        }

        It 'Reads a file with non-ASCII characters in its name' {
            $accented = Join-Path -Path $clipFolder -ChildPath 'démo – ünïcode.mp4'
            Copy-Item -LiteralPath $movingClip -Destination $accented
            (Get-VideoMetadata -Path $accented).Path | Should -Be (Get-Item -LiteralPath $accented).FullName
        }

        It 'Writes an error for a file that is not a video' {
            $notVideo = Join-Path -Path $clipFolder -ChildPath 'not a video.mp4'
            Set-Content -LiteralPath $notVideo -Value 'just text'
            Get-VideoMetadata -Path $notVideo -ErrorVariable problems -ErrorAction SilentlyContinue
            $problems.Where{ $_.ToString() -like '*Unable to read*' }.Count | Should -Be 1
        }
    }

    Context 'ConvertTo-Gif' {
        It 'Makes a GIF next to the video, at the size and frame rate asked for' {
            $gif = ConvertTo-Gif -Path $movingClip -Width 320 -Fps 10
            $gif.FullName | Should -Be (Join-Path -Path $clipFolder -ChildPath 'moving clip.gif')
            $metadata = Get-VideoMetadata -Path $gif.FullName -CountFrames
            $metadata.VideoCodec | Should -Be 'gif'
            $metadata.Width | Should -Be 320
            $metadata.Height | Should -Be 180
            $metadata.FrameCount | Should -Be 40
        }

        It 'Does not enlarge a video narrower than -Width' {
            $gif = ConvertTo-Gif -Path $pausedClip -Destination (Join-Path -Path $clipFolder -ChildPath 'not enlarged.gif') -Width 800
            (Get-VideoMetadata -Path $gif.FullName).Width | Should -Be 320
        }

        It 'Cuts to -Start and -End' {
            $gif = ConvertTo-Gif -Path $movingClip -Destination (Join-Path -Path $clipFolder -ChildPath 'cut.gif') -Start 1 -End '0:02.5' -Fps 10
            $metadata = Get-VideoMetadata -Path $gif.FullName -CountFrames
            $metadata.FrameCount | Should -Be 15
            $metadata.Duration.TotalSeconds | Should -BeGreaterOrEqual 1.4
            $metadata.Duration.TotalSeconds | Should -BeLessOrEqual 1.6
        }

        It 'Drops repeated frames with -RemoveDuplicateFrames, keeping the GIF about as long' {
            $full = ConvertTo-Gif -Path $pausedClip -Destination (Join-Path -Path $clipFolder -ChildPath 'paused full.gif')
            $deduplicated = ConvertTo-Gif -Path $pausedClip -Destination (Join-Path -Path $clipFolder -ChildPath 'paused dedup.gif') -RemoveDuplicateFrames
            $fullMetadata = Get-VideoMetadata -Path $full.FullName -CountFrames
            $deduplicatedMetadata = Get-VideoMetadata -Path $deduplicated.FullName -CountFrames
            $deduplicatedMetadata.FrameCount | Should -BeLessThan ($fullMetadata.FrameCount / 2)
            #A pause at the end can be cut short by up to half a second
            $deduplicatedMetadata.Duration.TotalSeconds | Should -BeGreaterOrEqual ($fullMetadata.Duration.TotalSeconds - 0.6)
        }

        It 'Works with every dither' -ForEach @(
            @{ Dither = 'Sierra2_4a' }
            @{ Dither = 'Sierra2' }
            @{ Dither = 'FloydSteinberg' }
            @{ Dither = 'Bayer' }
            @{ Dither = 'None' }
        ) {
            $gif = ConvertTo-Gif -Path $pausedClip -Destination (Join-Path -Path $clipFolder -ChildPath "dither $Dither.gif") -Dither $Dither -End 1
            $gif.FullName | Should -Exist
        }

        It 'Works through the version 1 alias and parameter names' {
            $gif = convert-mp4togif -mp4Path $pausedClip -gifPath (Join-Path -Path $clipFolder -ChildPath 'v1 alias.gif') -End 1
            $gif.FullName | Should -Exist
        }

        It 'Shows a percentage while converting' {
            Mock Write-Progress {}
            $null = ConvertTo-Gif -Path $movingClip -Destination (Join-Path -Path $clipFolder -ChildPath 'progress.gif') -Width 160
            Should -Invoke Write-Progress -ParameterFilter { $PercentComplete -gt 0 }
        }
    }
}
