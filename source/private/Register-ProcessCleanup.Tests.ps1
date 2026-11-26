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
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Register-ProcessCleanup' {
    BeforeEach {
        $child = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 60' -PassThru -WindowStyle Hidden
    }
    AfterEach {
        if(!$child.HasExited){ $child.Kill($true) }
    }

    It 'Ties a child process to this session' {
        Register-ProcessCleanup -Process $child | Should -BeTrue
    }

    It 'Ties several children to the same session' {
        $second = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 60' -PassThru -WindowStyle Hidden
        try{
            Register-ProcessCleanup -Process $child | Should -BeTrue
            Register-ProcessCleanup -Process $second | Should -BeTrue
        }finally{
            $second.Kill($true)
        }
    }

    It 'Starts a watchdog that leaves when the child does' -Skip:$IsWindows {
        $null = Register-ProcessCleanup -Process $child
        $watchdog = Get-Process | Where-Object { $_.CommandLine -like "*psScreenRecorder-watchdog*$($child.Id)*" }
        $watchdog | Should -Not -BeNullOrEmpty
        $child.Kill($true)
        Start-Sleep -Seconds 3
        $watchdog | ForEach-Object { $_.Refresh(); $_.HasExited } | Should -Not -Contain $false
    }

    It 'Warns, and carries on, when it can''t set up the cleanup' -Skip:(!$IsWindows) {
        Mock Initialize-ScreenRecorderNative { throw 'Add-Type is blocked' }
        Mock Write-Warning {}
        Register-ProcessCleanup -Process $child | Should -BeFalse
        Should -Invoke Write-Warning -ParameterFilter { $Message -like '*Add-Type is blocked*' }
    }
}
