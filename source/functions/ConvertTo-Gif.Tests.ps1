[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    #The transformation attribute is a class, so it has to load before the function that uses it
    $dependencies = @(
        'ToTimeSpanAttribute.ps1'
        'Invoke-FFmpeg.ps1'
        'Get-VideoMetadata.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'ConvertTo-Gif'
    . $fileName

    $videoFolder = Join-Path -Path $TestDrive -ChildPath 'my videos'
    $null = New-Item -ItemType Directory -Path $videoFolder -Force
    $clip = Join-Path -Path $videoFolder -ChildPath 'my clip.mp4'
    Set-Content -LiteralPath $clip -Value 'pretend video'
    $defaultGif = Join-Path -Path $videoFolder -ChildPath 'my clip.gif'
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-Gif' {
    BeforeEach {
        Remove-Item -Path (Join-Path -Path $videoFolder -ChildPath '*.gif') -ErrorAction Ignore
        #The output path is always the last argument, so write something there the way ffmpeg would
        Mock Invoke-FFmpeg {
            Set-Content -LiteralPath $ArgumentList[-1] -Value 'GIF89a'
            [PSCustomObject]@{ ExitCode = 0; StandardOutput = @(); StandardError = @() }
        }
        Mock Get-VideoMetadata { [PSCustomObject]@{ Duration = [timespan]::FromSeconds(20) } }
    }

    Context 'Where the GIF goes' {
        It 'Saves next to the video, with a .gif extension, and returns the file' {
            $result = ConvertTo-Gif -Path $clip
            $result | Should -BeOfType [System.IO.FileInfo]
            $result.FullName | Should -Be $defaultGif
        }

        It 'Saves into a folder given as the destination' {
            $outFolder = Join-Path -Path $TestDrive -ChildPath 'gif out'
            $null = New-Item -ItemType Directory -Path $outFolder -Force
            (ConvertTo-Gif -Path $clip -Destination $outFolder).FullName | Should -Be (Join-Path -Path $outFolder -ChildPath 'my clip.gif')
        }

        It 'Saves to a file name given as the destination' {
            $target = Join-Path -Path $TestDrive -ChildPath 'renamed.gif'
            (ConvertTo-Gif -Path $clip -Destination $target).FullName | Should -Be $target
        }

        It 'Writes an error, and leaves the file alone, when the GIF exists and -Force is not used' {
            Set-Content -LiteralPath $defaultGif -Value 'keep me'
            ConvertTo-Gif -Path $clip -ErrorVariable problems -ErrorAction SilentlyContinue
            $problems[0].ToString() | Should -BeLike '*already exists*-Force*'
            Get-Content -LiteralPath $defaultGif | Should -Be 'keep me'
            Should -Invoke Invoke-FFmpeg -Times 0 -Exactly
        }

        It 'Overwrites with -Force' {
            Set-Content -LiteralPath $defaultGif -Value 'replace me'
            $null = ConvertTo-Gif -Path $clip -Force
            Get-Content -LiteralPath $defaultGif | Should -Be 'GIF89a'
        }

        It 'Writes an error when the destination folder does not exist' {
            ConvertTo-Gif -Path $clip -Destination (Join-Path -Path $TestDrive -ChildPath 'no such folder/out.gif') -ErrorVariable problems -ErrorAction SilentlyContinue
            $problems[0].ToString() | Should -BeLike '*folder does not exist*'
        }

        It 'Refuses to overwrite the source' {
            $gifSource = Join-Path -Path $videoFolder -ChildPath 'already.gif'
            Set-Content -LiteralPath $gifSource -Value 'GIF89a'
            ConvertTo-Gif -Path $gifSource -Force -ErrorVariable problems -ErrorAction SilentlyContinue
            $problems[0].ToString() | Should -BeLike '*same file as the source*'
        }

        It 'Writes an error for a missing video' {
            ConvertTo-Gif -Path (Join-Path -Path $TestDrive -ChildPath 'missing.mp4') -ErrorVariable problems -ErrorAction SilentlyContinue
            $problems[0].ToString() | Should -BeLike '*not found*'
        }

        It 'Does nothing with -WhatIf' {
            $result = ConvertTo-Gif -Path $clip -WhatIf
            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-FFmpeg -Times 0 -Exactly
        }
    }

    Context 'The ffmpeg command' {
        It 'Uses the defaults: 10 fps, at most 800 wide, a 256 colour diff palette, looping forever' {
            $null = ConvertTo-Gif -Path $clip
            Should -Invoke Invoke-FFmpeg -ParameterFilter {
                $graph = $ArgumentList[[array]::IndexOf($ArgumentList,'-filter_complex') + 1]
                $graph -eq "[0:v]fps=10,scale='min(800,iw)':-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" -and
                ($ArgumentList -join ' ') -like '*-loop 0 -f gif*'
            }
        }

        It 'Passes the source as the input and the GIF as the output' {
            $null = ConvertTo-Gif -Path $clip
            Should -Invoke Invoke-FFmpeg -ParameterFilter {
                $ArgumentList[[array]::IndexOf($ArgumentList,'-i') + 1] -eq (Get-Item -LiteralPath $clip).FullName -and $ArgumentList[-1] -eq $defaultGif
            }
        }

        It 'Uses -Fps, -Width, -MaxColors and -Loop' {
            $null = ConvertTo-Gif -Path $clip -Fps 24 -Width 320 -MaxColors 64 -Loop -1
            Should -Invoke Invoke-FFmpeg -ParameterFilter {
                $joined = $ArgumentList -join ' '
                $joined -like '*fps=24,*' -and $joined -like "*scale='min(320,iw)'*" -and $joined -like '*max_colors=64*' -and $joined -like '*-loop -1*'
            }
        }

        It 'Keeps the source width with -Width 0' {
            $null = ConvertTo-Gif -Path $clip -Width 0
            Should -Invoke Invoke-FFmpeg -ParameterFilter { ($ArgumentList -join ' ') -notlike '*scale=*' }
        }

        It 'Uses ffmpeg''s name for the <Dither> dither' -ForEach @(
            @{ Dither = 'Sierra2'; Expected = 'dither=sierra2:' }
            @{ Dither = 'FloydSteinberg'; Expected = 'dither=floyd_steinberg:' }
            @{ Dither = 'Bayer'; Expected = 'dither=bayer:bayer_scale=3:' }
            @{ Dither = 'None'; Expected = 'dither=none:' }
        ) {
            $null = ConvertTo-Gif -Path $clip -Dither $Dither
            Should -Invoke Invoke-FFmpeg -ParameterFilter { ($ArgumentList -join ' ') -like "*$Expected*" }
        }

        It 'Drops repeated frames, keeping timing, with -RemoveDuplicateFrames' {
            $null = ConvertTo-Gif -Path $clip -RemoveDuplicateFrames -Fps 10
            Should -Invoke Invoke-FFmpeg -ParameterFilter {
                $joined = $ArgumentList -join ' '
                $joined -like '*fps=10,mpdecimate=max=5,*' -and $joined -like '*-fps_mode vfr*'
            }
        }

        It 'Keeps every frame without -RemoveDuplicateFrames' {
            $null = ConvertTo-Gif -Path $clip
            Should -Invoke Invoke-FFmpeg -ParameterFilter { ($ArgumentList -join ' ') -notlike '*mpdecimate*' -and $ArgumentList -notcontains '-fps_mode' }
        }
    }

    Context 'Cutting with -Start and -End' {
        It 'Seeks to -Start and lasts until -End' {
            $null = ConvertTo-Gif -Path $clip -Start 2.5 -End '0:10'
            Should -Invoke Invoke-FFmpeg -ParameterFilter {
                $ArgumentList[[array]::IndexOf($ArgumentList,'-ss') + 1] -eq '2.5' -and $ArgumentList[[array]::IndexOf($ArgumentList,'-t') + 1] -eq '7.5' -and
                [array]::IndexOf($ArgumentList,'-ss') -lt [array]::IndexOf($ArgumentList,'-i')
            }
        }

        It 'Writes decimals with a dot, whatever the current culture' {
            $savedCulture = [cultureinfo]::CurrentCulture
            try{
                [cultureinfo]::CurrentCulture = [cultureinfo]::GetCultureInfo('de-DE')
                $null = ConvertTo-Gif -Path $clip -Start 1.5
                Should -Invoke Invoke-FFmpeg -ParameterFilter { $ArgumentList -contains '1.5' }
            }finally{
                [cultureinfo]::CurrentCulture = $savedCulture
            }
        }

        It 'Uses only -t with just -End' {
            $null = ConvertTo-Gif -Path $clip -End 4
            Should -Invoke Invoke-FFmpeg -ParameterFilter { $ArgumentList -notcontains '-ss' -and $ArgumentList[[array]::IndexOf($ArgumentList,'-t') + 1] -eq '4' }
        }

        It 'Throws when -End is not after -Start' {
            { ConvertTo-Gif -Path $clip -Start 5 -End 3 } | Should -Throw '*must be after Start*'
        }

        It 'Throws for a negative -Start' {
            { ConvertTo-Gif -Path $clip -Start -1 } | Should -Throw '*cannot be negative*'
        }
    }

    Context 'Progress' {
        It 'Shows progress against the cut length when -End is given' {
            $null = ConvertTo-Gif -Path $clip -Start 2 -End 6
            Should -Invoke Invoke-FFmpeg -ParameterFilter { $ExpectedDuration -eq [timespan]::FromSeconds(4) -and $ProgressActivity -like '*my clip.mp4*' }
            Should -Invoke Get-VideoMetadata -Times 0 -Exactly
        }

        It 'Reads the source length for progress otherwise' {
            $null = ConvertTo-Gif -Path $clip -Start 5
            Should -Invoke Invoke-FFmpeg -ParameterFilter { $ExpectedDuration -eq [timespan]::FromSeconds(15) }
        }

        It 'Still converts when the source length can''t be read' {
            Mock Get-VideoMetadata { throw 'no ffprobe' }
            (ConvertTo-Gif -Path $clip).FullName | Should -Be $defaultGif
        }
    }

    Context 'Pipeline, errors and the version 1 names' {
        It 'Converts files from the pipeline' {
            $second = Join-Path -Path $videoFolder -ChildPath 'second.mkv'
            Set-Content -LiteralPath $second -Value 'pretend video'
            $results = Get-Item -LiteralPath $clip,$second | ConvertTo-Gif
            $results.Name | Should -Be @('my clip.gif','second.gif')
        }

        It 'Writes an error, and returns nothing, when ffmpeg fails' {
            Mock Invoke-FFmpeg { throw 'ffmpeg exited with code 1: Invalid data' }
            $result = ConvertTo-Gif -Path $clip -ErrorVariable problems -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            #ErrorVariable also records the exception the function caught, so look for the error it wrote
            $problems.Where{ $_.ToString() -like '*Unable to convert*Invalid data*' }.Count | Should -Be 1
        }

        It 'Has the convert-mp4togif alias, and the mp4Path and gifPath parameter aliases' {
            $command = Get-Command -Name $functionName
            $command.ScriptBlock.Attributes.Where{ $_ -is [System.Management.Automation.AliasAttribute] }.AliasNames | Should -Contain 'convert-mp4togif'
            $command.Parameters['Path'].Aliases | Should -Contain 'mp4Path'
            $command.Parameters['Destination'].Aliases | Should -Contain 'gifPath'
        }
    }
}
