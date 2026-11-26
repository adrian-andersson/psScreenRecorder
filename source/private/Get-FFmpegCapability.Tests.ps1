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
        'Invoke-FFmpeg.ps1'
        'Test-FFmpegEncoder.ps1'
        'Get-ScreenRecorderCacheFolder.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Get-FFmpegCapability'
    . $fileName

    #Trimmed from real ffmpeg 9.1 output, legends included, as those are what a parser trips over
    $filterOutput = @(
        'Filters:'
        '  T.. = Timeline support'
        '  .S. = Slice threading'
        '  A = Audio input/output'
        '  | = Source or sink filter'
        ' .. whisper           A->A       Transcribe audio using whisper.cpp.'
        ' .. ddagrab           |->V       Grab Windows Desktop images using Desktop Duplication API'
        ' .. gfxcapture        |->V       Capture graphics/screen content as a video source'
        ' TSC scale            V->V       Scale the input video size and/or convert the image format.'
    )
    $deviceOutput = @(
        'Devices:'
        ' D. = Demuxing supported'
        ' .E = Muxing supported'
        ' ---'
        ' D  dshow           DirectShow capture'
        ' D  gdigrab         GDI API Windows frame grabber'
        ' DE lavfi           Libavfilter virtual input device'
        '  E sdl,sdl2        SDL2 output device'
        ' D  video4linux2,v4l2 Video4Linux2 output device'
    )
    $encoderOutput = @(
        'Encoders:'
        ' V..... = Video'
        ' A..... = Audio'
        ' ------'
        ' V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)'
        ' V....D libx265              libx265 H.265 / HEVC (codec hevc)'
        ' V....D h264_nvenc           NVIDIA NVENC H.264 encoder (codec h264)'
        ' V....D av1_nvenc            NVIDIA NVENC av1 encoder (codec av1)'
        ' V....D libwebp              libwebp WebP image (codec webp)'
        ' A....D aac                  AAC (Advanced Audio Coding)'
    )

    $extension = $(if($IsWindows){'.exe'}else{''})
    $fakeFFmpeg = Join-Path -Path $TestDrive -ChildPath "ffmpeg$extension"
    Set-Content -LiteralPath $fakeFFmpeg -Value 'not really ffmpeg'
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Get-FFmpegCapability' {
    BeforeAll {
        $savedCache = $env:PSSCREENRECORDER_CACHE
    }
    AfterAll {
        $env:PSSCREENRECORDER_CACHE = $savedCache
    }
    BeforeEach {
        $script:psScreenRecorderCapability = @{}
        $env:PSSCREENRECORDER_CACHE = Join-Path -Path $TestDrive -ChildPath "cache $([guid]::NewGuid().ToString('N'))"
        $cacheFile = Join-Path -Path $env:PSSCREENRECORDER_CACHE -ChildPath 'ffmpeg-capability.json'
        Mock Invoke-FFmpeg {
            $lines = switch($ArgumentList[-1]){
                '-filters' { $filterOutput }
                '-devices' { $deviceOutput }
                '-encoders' { $encoderOutput }
            }
            [PSCustomObject]@{ ExitCode = 0; StandardOutput = $lines; StandardError = @() }
        }
        #As on an RTX 3090: listed, but AV1 can't be encoded
        Mock Test-FFmpegEncoder { $Encoder -ne 'av1_nvenc' }
    }

    Context 'Reading ffmpeg''s lists' {
        It 'Finds capture sources from both the filter and device lists, in order of preference' {
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1').CaptureSources | Should -Be @('gfxcapture','ddagrab','gdigrab')
        }

        It 'Lists only the encoders it knows, ignoring legends, audio and image encoders' {
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1').ListedEncoders | Should -Be @('libx264','libx265','h264_nvenc','av1_nvenc')
        }

        It 'Keeps only the listed encoders that pass a test encode' {
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1').WorkingEncoders | Should -Be @('libx264','libx265','h264_nvenc')
            Should -Invoke Test-FFmpegEncoder -Times 4 -Exactly
        }

        It 'Reads three-character filter flags from older builds' {
            Mock Invoke-FFmpeg {
                $lines = switch($ArgumentList[-1]){
                    '-filters' { @(' ... ddagrab           |->V       Grab Windows Desktop images') }
                    default { @() }
                }
                [PSCustomObject]@{ ExitCode = 0; StandardOutput = $lines; StandardError = @() }
            }
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '6.0').CaptureSources | Should -Be @('ddagrab')
        }

        It 'Splits device aliases such as video4linux2,v4l2' {
            Mock Invoke-FFmpeg {
                $lines = switch($ArgumentList[-1]){
                    '-devices' { @(' D  x11grab         X11 screen capture, using XCB','  E sdl,sdl2        SDL2 output device') }
                    default { @() }
                }
                [PSCustomObject]@{ ExitCode = 0; StandardOutput = $lines; StandardError = @() }
            }
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '6.1').CaptureSources | Should -Be @('x11grab')
        }
    }

    Context 'Caching in memory' {
        It 'Checks once per session' {
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            Should -Invoke Invoke-FFmpeg -Times 3 -Exactly
        }
    }

    Context 'Caching in a file' {
        It 'Saves what it found to the cache file' {
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $cacheFile | Should -Exist
            $saved = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json -DateKind String
            $saved.Entries.Count | Should -Be 1
            $saved.Entries[0].WorkingEncoders | Should -Be @('libx264','libx265','h264_nvenc')
            $saved.Entries[0].Fingerprint.Version | Should -Be '9.1'
        }

        It 'Reuses the file in a new session without running ffmpeg' {
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $script:psScreenRecorderCapability = @{}
            $result = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $result.FromCache | Should -BeTrue
            $result.WorkingEncoders | Should -Be @('libx264','libx265','h264_nvenc')
            Should -Invoke Invoke-FFmpeg -Times 3 -Exactly
            Should -Invoke Test-FFmpegEncoder -Times 4 -Exactly
        }

        It 'Checks again when the ffmpeg version changes' {
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $script:psScreenRecorderCapability = @{}
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.2').FromCache | Should -BeFalse
            Should -Invoke Invoke-FFmpeg -Times 6 -Exactly
        }

        It 'Checks again when the ffmpeg file changes' {
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $script:psScreenRecorderCapability = @{}
            Add-Content -LiteralPath $fakeFFmpeg -Value 'an update'
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1').FromCache | Should -BeFalse
        }

        It 'Checks again when the saved result is too old' {
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $script:psScreenRecorderCapability = @{}
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1' -MaxCacheAge ([timespan]::Zero)).FromCache | Should -BeFalse
        }

        It 'Checks again with -Refresh, ignoring both caches' {
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1' -Refresh).FromCache | Should -BeFalse
            Should -Invoke Invoke-FFmpeg -Times 6 -Exactly
        }

        It 'Checks again, and replaces the file, when it is unreadable' {
            $null = New-Item -ItemType Directory -Path $env:PSSCREENRECORDER_CACHE -Force
            Set-Content -LiteralPath $cacheFile -Value '{ this is not json'
            (Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1').FromCache | Should -BeFalse
            { Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'Keeps entries for other ffmpeg installs' {
            $otherFFmpeg = Join-Path -Path $TestDrive -ChildPath "other-ffmpeg$extension"
            Set-Content -LiteralPath $otherFFmpeg -Value 'another ffmpeg'
            $null = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $null = Get-FFmpegCapability -FFmpegPath $otherFFmpeg -Version '6.1'
            (Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json -DateKind String).Entries.Count | Should -Be 2
        }

        It 'Warns, and still returns the result, when the cache can''t be saved' {
            Mock Write-Warning {}
            Mock Set-Content { throw 'disk full' }
            $result = Get-FFmpegCapability -FFmpegPath $fakeFFmpeg -Version '9.1'
            $result.WorkingEncoders | Should -Not -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like '*Unable to save*' }
        }
    }
}
