function Measure-MFNestedFunction
{
    <#
        .SYNOPSIS
            Functions should not be defined inside other functions. Give each one its own file, in source/private if it is a helper.

        .DESCRIPTION
            A function defined inside another can't be tested on its own, can't be reused, and is easy to miss,
            as it doesn't have a file named after it. It is also defined again every time the outer function runs.

            Move it to its own file instead, and ModuleForge will build it into the module as usual:
                source/private/<area>/<name>.ps1
                source/private/<area>/<name>.Tests.ps1

            Functions inside a script block, such as one passed to Start-Job or Invoke-Command, are not reported,
            as that code runs somewhere the module's functions can't be seen. Functions inside a class method are reported.

            To keep one on purpose, add this to the outer function:
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('Measure-MFNestedFunction', '', Justification = 'Why')]
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

        $functions = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach($function in $functions)
        {
            #A class method's body is itself a function definition, held by the method. That is the method, not a nested function
            if($function.Parent -is [System.Management.Automation.Language.FunctionMemberAst]){ continue }

            #Walk up to the function or class method this one sits in. A script block on the way means it runs somewhere else
            $outer = $null
            $parent = $function.Parent
            while($parent)
            {
                if($parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst]){ break }
                if($parent -is [System.Management.Automation.Language.FunctionDefinitionAst])
                {
                    #Report a class method by its class and name
                    $outer = if($parent.Parent -is [System.Management.Automation.Language.FunctionMemberAst]){ $parent.Parent }else{ $parent }
                    break
                }
                $parent = $parent.Parent
            }
            if(!$outer){ continue }

            $outerName = if($outer -is [System.Management.Automation.Language.FunctionMemberAst]){
                "$($outer.Parent.Name)::$($outer.Name)"
            }else{
                $outer.Name
            }

            [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = "Function '$($function.Name)' is defined inside '$outerName'. Move it to its own file, such as source/private, so it can be tested and reused"
                Extent   = $function.Extent
                RuleName = 'Measure-MFNestedFunction'
                Severity = 'Warning'
            }
        }
    }
}
Export-ModuleMember -Function Measure-*
