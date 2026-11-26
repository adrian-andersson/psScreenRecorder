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
        'Find-FFmpeg.ps1'
        'Resolve-FFmpegExecutable.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Invoke-FFmpeg'
    . $fileName

    #pwsh stands in for ffmpeg: a real native executable on every platform, which can write to stdout and stderr and exit with any code
    $fakeTool = (Get-Process -Id $PID).Path
    $fakeScript = Join-Path -Path $TestDrive -ChildPath 'fakeTool.ps1'
    Set-Content -LiteralPath $fakeScript -Value @'
foreach($argument in $args){ [Console]::Out.WriteLine("arg:$argument") }
[Console]::Out.WriteLine('out_time_us=1500000')
[Console]::Error.WriteLine('a warning on stderr')
[Console]::Error.WriteLine('the real error')
exit [int]$env:PSSR_FAKE_EXIT
'@
    $baseArguments = @('-NoProfile','-NonInteractive','-File',$fakeScript)

    #ffmpeg takes its progress switches first, which pwsh would reject, so progress tests use a plain native script instead
    if($IsWindows)
    {
        $fakeProgressTool = Join-Path -Path $TestDrive -ChildPath 'fakeProgress.cmd'
        Set-Content -LiteralPath $fakeProgressTool -Value @(
            '@echo off'
            'for %%a in (%*) do echo arg:%%~a'
            'echo out_time_us=%PSSR_FAKE_TIME%'
            'echo progress=end'
        )
    }else{
        $fakeProgressTool = Join-Path -Path $TestDrive -ChildPath 'fakeProgress.sh'
        Set-Content -LiteralPath $fakeProgressTool -Value @(
            '#!/bin/sh'
            'for a in "$@"; do echo "arg:$a"; done'
            'echo "out_time_us=$PSSR_FAKE_TIME"'
            'echo "progress=end"'
        )
        chmod +x $fakeProgressTool
    }
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-FFmpeg' {
    BeforeEach {
        $env:PSSR_FAKE_EXIT = '0'
        $env:PSSR_FAKE_TIME = '1500000'
    }
    AfterAll {
        Remove-Item -Path 'env:PSSR_FAKE_EXIT','env:PSSR_FAKE_TIME' -ErrorAction Ignore
    }

    Context 'Running an executable' {
        It 'Separates stdout from stderr and returns exit code 0' {
            $result = Invoke-FFmpeg -ExecutablePath $fakeTool -ArgumentList $baseArguments
            $result.ExitCode | Should -Be 0
            $result.StandardOutput | Should -Contain 'out_time_us=1500000'
            $result.StandardError | Should -Contain 'the real error'
            $result.StandardOutput | Should -Not -Contain 'the real error'
            $result.PSTypeNames | Should -Contain 'psScreenRecorder.FFmpegResult'
        }

        It 'Passes arguments with spaces, quotes and filter syntax through unchanged' {
            $awkward = @('my clip.mp4', "[0:v]scale='min(800,iw)':-1,split[a][b];[a]palettegen[p]", 'it''s "quoted"')
            $result = Invoke-FFmpeg -ExecutablePath $fakeTool -ArgumentList ($baseArguments + $awkward)
            foreach($argument in $awkward)
            {
                $result.StandardOutput | Should -Contain "arg:$argument"
            }
        }

        It 'Passes an empty argument through, as macOS device listing needs for -i ""' {
            $result = Invoke-FFmpeg -ExecutablePath $fakeTool -ArgumentList ($baseArguments + @('before','','after'))
            $result.StandardOutput | Should -Contain 'arg:'
            $result.StandardOutput | Should -Contain 'arg:after'
        }

        It 'Throws on a non-zero exit, with the exit code and the end of stderr' {
            $env:PSSR_FAKE_EXIT = '3'
            { Invoke-FFmpeg -ExecutablePath $fakeTool -ArgumentList $baseArguments } | Should -Throw '*exited with code 3*the real error*'
        }

        It 'Returns the result instead of throwing with -IgnoreExitCode' {
            $env:PSSR_FAKE_EXIT = '1'
            $result = Invoke-FFmpeg -ExecutablePath $fakeTool -ArgumentList $baseArguments -IgnoreExitCode
            $result.ExitCode | Should -Be 1
            $result.StandardError | Should -Contain 'the real error'
        }

        It 'Still throws its own error when native command errors are turned on' {
            $env:PSSR_FAKE_EXIT = '2'
            $PSNativeCommandUseErrorActionPreference = $true
            { Invoke-FFmpeg -ExecutablePath $fakeTool -ArgumentList $baseArguments -ErrorAction Stop } | Should -Throw '*exited with code 2*'
        }
    }

    Context 'Progress' {
        It 'Adds the progress arguments in front of the others' {
            Mock Write-Progress {}
            $result = Invoke-FFmpeg -ExecutablePath $fakeProgressTool -ArgumentList 'first','second' -ProgressActivity 'Testing'
            $result.StandardOutput | Select-Object -First 5 | Should -Be @('arg:-progress','arg:pipe:1','arg:-nostats','arg:first','arg:second')
        }

        It 'Leaves the progress arguments out when no activity is given' {
            $result = Invoke-FFmpeg -ExecutablePath $fakeProgressTool -ArgumentList 'first'
            $result.StandardOutput | Should -Not -Contain 'arg:-progress'
        }

        It 'Reports a percentage from out_time_us when the expected duration is known' {
            Mock Write-Progress {}
            $null = Invoke-FFmpeg -ExecutablePath $fakeProgressTool -ArgumentList 'x' -ProgressActivity 'Testing' -ExpectedDuration ([timespan]::FromSeconds(3))
            Should -Invoke Write-Progress -ParameterFilter { $Activity -eq 'Testing' -and $PercentComplete -eq 50 }
            Should -Invoke Write-Progress -ParameterFilter { $Completed }
        }

        It 'Never reports more than 100 percent' {
            Mock Write-Progress {}
            $env:PSSR_FAKE_TIME = '9000000'
            $null = Invoke-FFmpeg -ExecutablePath $fakeProgressTool -ArgumentList 'x' -ProgressActivity 'Testing' -ExpectedDuration ([timespan]::FromSeconds(3))
            Should -Invoke Write-Progress -ParameterFilter { $PercentComplete -eq 100 }
        }

        It 'Reports elapsed time without a percentage when the duration is unknown' {
            Mock Write-Progress {}
            $env:PSSR_FAKE_TIME = '61000000'
            $null = Invoke-FFmpeg -ExecutablePath $fakeProgressTool -ArgumentList 'x' -ProgressActivity 'Testing'
            Should -Invoke Write-Progress -ParameterFilter { $Status -eq '00:01:01' -and -not $PSBoundParameters.ContainsKey('PercentComplete') }
        }
    }

    Context 'Finding the executable' {
        It 'Uses ffmpeg from Find-FFmpeg when no executable is given' {
            Mock Find-FFmpeg { [PSCustomObject]@{ FFmpegPath = $fakeTool; FFprobePath = $null } }
            $result = Invoke-FFmpeg -ArgumentList $baseArguments
            $result.ExitCode | Should -Be 0
            Should -Invoke Find-FFmpeg -Times 1
        }

        It 'Uses ffprobe from Find-FFmpeg when asked for ffprobe' {
            Mock Find-FFmpeg { [PSCustomObject]@{ FFmpegPath = 'not-this-one'; FFprobePath = $fakeTool } }
            $result = Invoke-FFmpeg -Tool ffprobe -ArgumentList $baseArguments
            $result.ExitCode | Should -Be 0
        }

        It 'Throws a clear error when ffprobe is wanted but was not found' {
            Mock Find-FFmpeg { [PSCustomObject]@{ FFmpegPath = $fakeTool; FFprobePath = $null } }
            { Invoke-FFmpeg -Tool ffprobe -ArgumentList '-version' } | Should -Throw '*ffprobe was not found*'
        }
    }
}
