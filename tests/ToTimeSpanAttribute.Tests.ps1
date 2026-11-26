#Classes aren't in the folders Pester looks in for tests, so tests for the ones in source/validationClasses live here
BeforeAll {
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path -Path $projectRoot -ChildPath 'source' -AdditionalChildPath 'validationClasses','ToTimeSpanAttribute.ps1')

    #A function to hang the attribute on, defined after the class has loaded
    . ([scriptblock]::Create('function Get-TestTime { param([ToTimeSpan()][timespan]$Time) $Time }'))
}

Describe 'ToTimeSpanAttribute' {
    It 'Reads <Value> as <Expected>' -ForEach @(
        @{ Value = 5; Expected = '00:00:05' }
        @{ Value = 2.5; Expected = '00:00:02.5' }
        @{ Value = '90'; Expected = '00:01:30' }
        @{ Value = '0.25'; Expected = '00:00:00.25' }
        @{ Value = '1:30'; Expected = '00:01:30' }
        @{ Value = '01:30.5'; Expected = '00:01:30.5' }
        @{ Value = '1:02:03'; Expected = '01:02:03' }
        @{ Value = ' 10 '; Expected = '00:00:10' }
    ) {
        Get-TestTime -Time $Value | Should -Be ([timespan]::Parse($Expected, [cultureinfo]::InvariantCulture))
    }

    It 'Passes a TimeSpan through unchanged' {
        Get-TestTime -Time ([timespan]::FromMinutes(3)) | Should -Be ([timespan]::FromMinutes(3))
    }

    It 'Reads decimals with a dot, whatever the current culture' {
        $savedCulture = [cultureinfo]::CurrentCulture
        try{
            [cultureinfo]::CurrentCulture = [cultureinfo]::GetCultureInfo('de-DE')
            Get-TestTime -Time '2.5' | Should -Be ([timespan]::FromSeconds(2.5))
        }finally{
            [cultureinfo]::CurrentCulture = $savedCulture
        }
    }

    It 'Throws a helpful error for <Value>' -ForEach @(
        @{ Value = 'soon' }
        @{ Value = '1:2:3:4' }
        @{ Value = 'a:30' }
    ) {
        { Get-TestTime -Time $Value } | Should -Throw '*Use seconds*mm:ss*'
    }
}
