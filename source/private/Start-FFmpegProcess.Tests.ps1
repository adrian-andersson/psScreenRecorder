[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#Start-FFmpegProcess and Stop-FFmpegProcess are tested together: one starts what the other stops
BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    foreach($dependency in @('Stop-FFmpegProcess.ps1','Register-ProcessCleanup.ps1','Initialize-ScreenRecorderNative.ps1'))
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Start-FFmpegProcess'
    . $fileName

    #pwsh stands in for ffmpeg: it echoes its arguments, then waits for 'q' on stdin as ffmpeg does, or ignores stdin
    $fakeTool = (Get-Process -Id $PID).Path
    $fakeScript = Join-Path -Path $TestDrive -ChildPath 'fakeRecorder.ps1'
    Set-Content -LiteralPath $fakeScript -Value @'
param([string]$Mode = 'listen')
foreach($argument in $args){ [Console]::Out.WriteLine("arg:$argument") }
[Console]::Error.WriteLine('recording started')
if($Mode -eq 'ignore'){ Start-Sleep -Seconds 60; exit 0 }
if($Mode -eq 'fail'){ [Console]::Error.WriteLine('Could not open capture device'); exit 5 }
while($true){
    $character = [Console]::In.Read()
    if($character -lt 0){ [Console]::Error.WriteLine('stdin closed'); exit 2 }
    if([char]$character -eq 'q'){ [Console]::Error.WriteLine('stopping cleanly'); exit 0 }
}
'@
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Start-FFmpegProcess and Stop-FFmpegProcess' {
    It 'Starts the process, and stops it cleanly by sending q' {
        $handle = Start-FFmpegProcess -FFmpegPath $fakeTool -ArgumentList '-NoProfile','-File',$fakeScript,'listen'
        $handle.PSTypeNames | Should -Contain 'psScreenRecorder.FFmpegProcess'
        $handle.Process.HasExited | Should -BeFalse
        $handle.ProcessId | Should -Be $handle.Process.Id

        $exit = Stop-FFmpegProcess -Handle $handle
        $exit.ExitCode | Should -Be 0
        $exit.Killed | Should -BeFalse
        $exit.StandardError | Should -BeLike '*stopping cleanly*'
    }

    It 'Passes each argument through whole, spaces and all' {
        $handle = Start-FFmpegProcess -FFmpegPath $fakeTool -ArgumentList '-NoProfile','-File',$fakeScript,'listen','my recording.mkv','crop=trunc(iw/2)*2:trunc(ih/2)*2'
        $null = Stop-FFmpegProcess -Handle $handle
        $output = $handle.StandardOutputTask.GetAwaiter().GetResult()
        $output | Should -BeLike '*arg:my recording.mkv*'
        $output | Should -BeLike '*arg:crop=trunc(iw/2)*2:trunc(ih/2)*2*'
    }

    It 'Kills the process, with a warning, when it ignores q past the timeout' {
        Mock Write-Warning {}
        $handle = Start-FFmpegProcess -FFmpegPath $fakeTool -ArgumentList '-NoProfile','-File',$fakeScript,'ignore'
        $exit = Stop-FFmpegProcess -Handle $handle -Timeout ([timespan]::FromSeconds(2))
        $exit.Killed | Should -BeTrue
        $handle.Process.HasExited | Should -BeTrue
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*did not stop*' }
    }

    It 'Reports the exit code and error of a process that already ended' {
        $handle = Start-FFmpegProcess -FFmpegPath $fakeTool -ArgumentList '-NoProfile','-File',$fakeScript,'fail'
        $null = $handle.Process.WaitForExit(30000)
        $exit = Stop-FFmpegProcess -Handle $handle
        $exit.ExitCode | Should -Be 5
        $exit.Killed | Should -BeFalse
        $exit.StandardError | Should -BeLike '*Could not open capture device*'
    }

    It 'Does not start anything with -WhatIf' {
        Start-FFmpegProcess -FFmpegPath $fakeTool -ArgumentList '-NoProfile' -WhatIf | Should -BeNullOrEmpty
    }
}
