[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

#The native helper and its thin wrappers, on a real Windows desktop. Elsewhere, only the refusal is tested
BeforeDiscovery {
    #The overlay needs a real desktop. CI runners may not have one, so there it runs only when asked for
    $interactiveDesktop = $IsWindows -and ([Environment]::GetEnvironmentVariable('PSSCREENRECORDER_TEST_CAPTURE') -eq '1' -or [Environment]::GetEnvironmentVariable('CI') -ne 'true')
}

BeforeAll {
    $sourcePath = $PSScriptRoot
    while($sourcePath -and (Split-Path -Path $sourcePath -Leaf) -ne 'source'){ $sourcePath = Split-Path -Path $sourcePath -Parent }
    $sourceMap = @{}
    Get-ChildItem -Path $sourcePath -Recurse -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '*.Tests.ps1' } | ForEach-Object {
        if(-not $sourceMap.ContainsKey($_.Name)){ $sourceMap[$_.Name] = $_.FullName }
    }
    $dependencies = @(
        'Get-NativeMonitorInfo.ps1'
        'Get-NativeWindowInfo.ps1'
        'Get-ForegroundWindowHandle.ps1'
        'Invoke-NativeRegionSelection.ps1'
    )
    foreach($dependency in $dependencies)
    {
        if($sourceMap.ContainsKey($dependency)){ . $sourceMap[$dependency] }else{ Write-Warning "Dependency not found under source: $dependency" }
    }
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Initialize-ScreenRecorderNative'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Initialize-ScreenRecorderNative' {
    It 'Refuses to load anywhere but Windows' -Skip:$IsWindows {
        { Initialize-ScreenRecorderNative } | Should -Throw '*only available on Windows*'
    }

    Context 'On Windows' -Skip:(!$IsWindows) {
        It 'Compiles the helper and returns its type, then returns the same type without compiling again' {
            $native = Initialize-ScreenRecorderNative
            $native | Should -BeOfType [type]
            $native.FullName | Should -Match '^PsScreenRecorder\.H[0-9a-f]{10}\.Native$'
            Initialize-ScreenRecorderNative | Should -Be $native
        }

        It 'Finds its own helper even when an older version''s is already loaded under the old fixed name' {
            #prev002 compiled PsScreenRecorder.Native without SelectRegion. In the same session, prev003 must not use it
            if(!('PsScreenRecorder.Native' -as [type]))
            {
                Add-Type -TypeDefinition 'namespace PsScreenRecorder { public static class Native { public static int OlderVersion() { return 2; } } }'
            }
            $script:psScreenRecorderNative = $null
            $native = Initialize-ScreenRecorderNative
            $native.FullName | Should -Not -Be 'PsScreenRecorder.Native'
            $native.GetMethod('SelectRegion') | Should -Not -BeNullOrEmpty
            $native.GetMethod('KillWithThisProcess') | Should -Not -BeNullOrEmpty
        }

        It 'Lists at least one monitor, with a size and a primary' {
            $monitors = @(Get-NativeMonitorInfo)
            $monitors.Count | Should -BeGreaterThan 0
            $monitors[0].Width | Should -BeGreaterThan 0
            @($monitors.Where{ $_.IsPrimary }).Count | Should -Be 1
        }

        It 'Returns nothing for a window handle that does not exist' {
            Get-NativeWindowInfo -Handle 1 | Should -BeNullOrEmpty
        }

        It 'Lists windows without failing, and reports the focused window as a number' {
            { Get-NativeWindowInfo } | Should -Not -Throw
            Get-ForegroundWindowHandle | Should -BeOfType [long]
        }

        It 'Returns the area dragged out on the region overlay, ignoring a click without a drag' -Skip:(!$interactiveDesktop) {
            $helper = Get-Content -Raw -LiteralPath (Join-Path -Path (Split-Path -Path $sourcePath -Parent) -ChildPath 'tests/helpers/Send-RegionSelectorInput.ps1')
            $driver = [powershell]::Create().AddScript($helper).AddParameter('Gesture', 'Drag').AddParameter('From', @(100,50)).AddParameter('To', @(500,350))
            try{
                $async = $driver.BeginInvoke()
                $selection = Invoke-NativeRegionSelection
                $driver.EndInvoke($async) | Should -Be 'posted'
            }finally{
                $driver.Dispose()
            }
            $origin = @(Get-NativeMonitorInfo | ForEach-Object { $_.Left }) | Measure-Object -Minimum
            $top = @(Get-NativeMonitorInfo | ForEach-Object { $_.Top }) | Measure-Object -Minimum
            $selection | Should -Be @(($origin.Minimum + 100), ($top.Minimum + 50), 400, 300)
        }

        It 'Returns nothing when the region overlay is cancelled with a right-click' -Skip:(!$interactiveDesktop) {
            $helper = Get-Content -Raw -LiteralPath (Join-Path -Path (Split-Path -Path $sourcePath -Parent) -ChildPath 'tests/helpers/Send-RegionSelectorInput.ps1')
            $driver = [powershell]::Create().AddScript($helper).AddParameter('Gesture', 'Cancel')
            try{
                $async = $driver.BeginInvoke()
                Invoke-NativeRegionSelection | Should -BeNullOrEmpty
                $null = $driver.EndInvoke($async)
            }finally{
                $driver.Dispose()
            }
        }

        It 'Puts the thread''s DPI awareness back afterwards' {
            Add-Type -Namespace PsScreenRecorderTest -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetThreadDpiAwarenessContext();
[DllImport("user32.dll")] public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
'@ -ErrorAction SilentlyContinue
            $before = [PsScreenRecorderTest.Dpi]::GetAwarenessFromDpiAwarenessContext([PsScreenRecorderTest.Dpi]::GetThreadDpiAwarenessContext())
            $null = Get-NativeMonitorInfo
            [PsScreenRecorderTest.Dpi]::GetAwarenessFromDpiAwarenessContext([PsScreenRecorderTest.Dpi]::GetThreadDpiAwarenessContext()) | Should -Be $before
        }
    }
}
