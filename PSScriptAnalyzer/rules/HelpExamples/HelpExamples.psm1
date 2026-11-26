function Measure-MFHelpExample
{
    <#
        .SYNOPSIS
            Public functions should include at least one .EXAMPLE in their comment-based help.

        .DESCRIPTION
            The docs site is generated from comment-based help, and an example is the first thing most
            people look for. Only functions in source/functions are checked, as those are the ones exported.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    PARAM(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    process{
        #Called for every script block in a file. Only the file's top level is checked, so nothing is reported twice
        if($null -ne $ScriptBlockAst.Parent){ return }
        if($ScriptBlockAst.Extent.File -notmatch '[\\/]functions[\\/]'){ return }

        $functions = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        foreach($function in $functions)
        {
            $help = $function.GetHelpContent()
            if(!$help -or !$help.Examples -or $help.Examples.Count -lt 1)
            {
                [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                    Message  = "Function '$($function.Name)' has no .EXAMPLE in its comment-based help"
                    Extent   = $function.Extent
                    RuleName = 'Measure-MFHelpExample'
                    Severity = 'Warning'
                }
            }
        }
    }
}
Export-ModuleMember -Function Measure-*
