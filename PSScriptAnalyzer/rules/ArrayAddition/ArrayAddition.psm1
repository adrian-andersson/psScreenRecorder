function Measure-MFArrayAddition
{
    <#
        .SYNOPSIS
            Adding to an array with += copies the whole array each time. Use a generic list, or collect a loop's output.

        .DESCRIPTION
            Arrays are a fixed size, so $results += $item makes a new array and copies every item into it.
            In a loop that grows with the square of the item count. PowerShell 7.5 made it faster, but it still
            copies, and Windows PowerShell 5.1 does not have that improvement.

            Use a generic list instead:
                $results = [System.Collections.Generic.List[string]]::new()
                $results.Add($item)

            Or assign the loop's output directly:
                $results = foreach($item in $items){ $item }

            Only variables the same function or script sets up as an array are checked, such as $results = @()
            or a [string[]] parameter, as += on a number or a string is fine. Inside a loop it is a Warning,
            elsewhere it is Information.
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

        #The function a node belongs to, or the file itself, as variables are set up and used within one of those
        $getScope = {
            param($node)
            $parent = $node.Parent
            while($parent -and $parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst]){ $parent = $parent.Parent }
            if($parent){ $parent }else{ $ScriptBlockAst }
        }

        $isArrayType = {
            param([System.Management.Automation.Language.ITypeName]$typeName)
            $typeName.IsArray -or $typeName.FullName -in 'array','System.Array'
        }

        #Variables set up as arrays, by scope: $x = @(...), $x = 1,2, [string[]]$x = ..., [array]$x = ..., or an array parameter
        $arrayVariables = @{}
        $addArrayVariable = {
            param($node,[string]$name)
            $scope = & $getScope $node
            if(!$arrayVariables.ContainsKey($scope)){ $arrayVariables[$scope] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
            $null = $arrayVariables[$scope].Add($name)
        }

        $assignments = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
        foreach($assignment in $assignments.Where{ $_.Operator -eq 'Equals' })
        {
            $left = $assignment.Left
            if($left -is [System.Management.Automation.Language.ConvertExpressionAst] -and $left.Child -is [System.Management.Automation.Language.VariableExpressionAst])
            {
                if(& $isArrayType $left.Type.TypeName){ & $addArrayVariable $assignment $left.Child.VariablePath.UserPath }
                continue
            }
            if($left -isnot [System.Management.Automation.Language.VariableExpressionAst]){ continue }
            $right = $assignment.Right
            if($right -is [System.Management.Automation.Language.CommandExpressionAst] -and (
                $right.Expression -is [System.Management.Automation.Language.ArrayExpressionAst] -or
                $right.Expression -is [System.Management.Automation.Language.ArrayLiteralAst]))
            {
                & $addArrayVariable $assignment $left.VariablePath.UserPath
            }
        }

        $parameters = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true)
        foreach($parameter in $parameters)
        {
            $typeConstraint = $parameter.Attributes.Where{ $_ -is [System.Management.Automation.Language.TypeConstraintAst] } | Select-Object -First 1
            if($typeConstraint -and (& $isArrayType $typeConstraint.TypeName))
            {
                & $addArrayVariable $parameter $parameter.Name.VariablePath.UserPath
            }
        }

        foreach($assignment in $assignments.Where{ $_.Operator -eq 'PlusEquals' -and $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] })
        {
            $name = $assignment.Left.VariablePath.UserPath
            $scope = & $getScope $assignment
            if(!$arrayVariables.ContainsKey($scope) -or !$arrayVariables[$scope].Contains($name)){ continue }

            #In a loop if a loop statement, a ForEach-Object script block or a .ForEach() call sits between it and its function
            $inLoop = $false
            $parent = $assignment.Parent
            while($parent -and $parent -ne $scope)
            {
                if($parent -is [System.Management.Automation.Language.LoopStatementAst]){ $inLoop = $true; break }
                if($parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst])
                {
                    $owner = $parent.Parent
                    if($owner -is [System.Management.Automation.Language.CommandAst] -and $owner.GetCommandName() -in 'ForEach-Object','%','foreach'){ $inLoop = $true; break }
                    if($owner -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $owner.Member.Extent.Text -eq 'ForEach'){ $inLoop = $true; break }
                }
                $parent = $parent.Parent
            }

            $fix = "Use a [System.Collections.Generic.List[T]] and its .Add() method, or assign the loop's output directly: `$$name = foreach(...){ ... }"
            [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = if($inLoop){
                    "`$$name += in a loop copies the whole array on every pass. $fix"
                }else{
                    "`$$name += copies the whole array to add to it. $fix"
                }
                Extent   = $assignment.Extent
                RuleName = 'Measure-MFArrayAddition'
                Severity = if($inLoop){ 'Warning' }else{ 'Information' }
            }
        }
    }
}
Export-ModuleMember -Function Measure-*
