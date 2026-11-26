[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#That the child really does end with its parent is tested end to end in tests/Recording.Integration.Tests.ps1
BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    foreach($dependency in @('Initialize-ScreenRecorderNative.ps1'))
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Register-ProcessCleanup'
    . $fileName

    #A long-running child to tie to this session. -WindowStyle only exists on Windows
    $childSplat = @{
        FilePath = (Get-Process -Id $PID).Path
        ArgumentList = '-NoProfile','-Command','Start-Sleep -Seconds 60'
        PassThru = $true
    }
    if($IsWindows)
    {
        $childSplat.WindowStyle = 'Hidden'
    }
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Register-ProcessCleanup' {
    BeforeEach {
        $child = Start-Process @childSplat
    }
    AfterEach {
        if($child -and !$child.HasExited){ $child.Kill($true) }
    }

    It 'Ties a child process to this session' {
        Register-ProcessCleanup -Process $child | Should -BeTrue
    }

    It 'Ties several children to the same session' {
        $second = Start-Process @childSplat
        try{
            Register-ProcessCleanup -Process $child | Should -BeTrue
            Register-ProcessCleanup -Process $second | Should -BeTrue
        }finally{
            $second.Kill($true)
        }
    }

    It 'Starts a watchdog that leaves when the child does' -Skip:$IsWindows {
        $null = Register-ProcessCleanup -Process $child
        #ps shows full command lines on both macOS and Linux, which Get-Process doesn't everywhere
        $findWatchdog = { @(& /bin/ps -A -o pid=,args= | Where-Object { $_ -like '*psScreenRecorder-watchdog*' -and $_ -match " $($child.Id)\s*$" }) }
        (& $findWatchdog).Count | Should -BeGreaterThan 0
        $child.Kill($true)
        $deadline = [datetime]::Now.AddSeconds(10)
        while((& $findWatchdog).Count -gt 0 -and [datetime]::Now -lt $deadline)
        {
            Start-Sleep -Milliseconds 250
        }
        (& $findWatchdog).Count | Should -Be 0
    }

    It 'Warns, and carries on, when it can''t set up the cleanup' -Skip:(!$IsWindows) {
        Mock Initialize-ScreenRecorderNative { throw 'Add-Type is blocked' }
        Mock Write-Warning {}
        Register-ProcessCleanup -Process $child | Should -BeFalse
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*Add-Type is blocked*' }
    }
}
