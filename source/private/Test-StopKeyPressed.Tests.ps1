[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification='PSScriptAnalyzer cannot see Pester BeforeAll scoping')]
param()

BeforeAll {
    $fileName = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $functionName = 'Test-StopKeyPressed'
    . $fileName
}

Describe 'Check Clean Environment' {
    It 'Should have loaded the script directly, not from the module' {
        $PSCommandPath.Replace('.Tests.ps1', '.ps1') | Should -Be $fileName
        (Get-Command $functionName).Source | Should -BeNullOrEmpty
    }
}

Describe 'Test-StopKeyPressed' {
    It 'Returns true or false, without waiting' {
        Test-StopKeyPressed | Should -BeOfType [bool]
    }
}
