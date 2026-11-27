function Get-CaptureTargetCompletion
{
    <#
        .SYNOPSIS
            Tab completion for -Window and -Monitor: the open windows' titles, or the monitors' numbers

        .DESCRIPTION
            Used by the ArgumentCompleter attributes on Start-ScreenRecording, Invoke-ScreenRecording and
            Get-CaptureTarget, so pressing Tab after -Window offers the windows that are open, and after -Monitor
            the monitors, with their size, as tooltips.

            Window titles are matched anywhere against what's been typed so far, then quoted. Their wildcard
            characters ([, ], * and ?) are escaped, as titles such as 'notes.md [Preview]' otherwise wouldn't
            match themselves.

            Returns nothing, rather than an error, where the list isn't available, so Tab never shows one.

        .NOTES
            Author: Adrian Andersson

        .EXAMPLE
            Get-CaptureTargetCompletion -Kind Window -WordToComplete 'code'

            #### DESCRIPTION
            Completions for every window whose title contains 'code'.
    #>

    [CmdletBinding()]
    [OutputType([System.Management.Automation.CompletionResult])]
    PARAM(
        #What to complete
        [Parameter(Mandatory)]
        [ValidateSet('Window','Monitor')]
        [string]$Kind,
        #What has been typed so far
        [Parameter()]
        [AllowEmptyString()]
        [string]$WordToComplete = ''
    )
    process{
        $typed = $WordToComplete.Trim('''','"')
        try{
            if($Kind -eq 'Monitor')
            {
                foreach($monitor in @(Get-CaptureTarget -ErrorAction Stop))
                {
                    if($typed -and "$($monitor.Index)" -notlike "$typed*")
                    {
                        continue
                    }
                    $description = "$($monitor.Index): $($monitor.Name)$(if($monitor.Width){" $($monitor.Width)x$($monitor.Height)"})$(if($monitor.IsPrimary){' (primary)'})"
                    [System.Management.Automation.CompletionResult]::new("$($monitor.Index)", $description, 'ParameterValue', $description)
                }
                return
            }

            $seen = [System.Collections.Generic.HashSet[string]]::new()
            foreach($window in @(Get-CaptureTarget -Window -ErrorAction Stop))
            {
                if(!$window.Title -or !$seen.Add($window.Title))
                {
                    continue
                }
                if($typed -and $window.Title -notlike "*$([System.Management.Automation.WildcardPattern]::Escape($typed))*" -and $window.ProcessName -notlike "$([System.Management.Automation.WildcardPattern]::Escape($typed))*")
                {
                    continue
                }
                $escaped = [System.Management.Automation.WildcardPattern]::Escape($window.Title).Replace("'","''")
                $listText = $(if($window.Title.Length -gt 70){"$($window.Title.Substring(0,67))..."}else{$window.Title})
                [System.Management.Automation.CompletionResult]::new("'$escaped'", $listText, 'ParameterValue', "$($window.Title) ($($window.ProcessName))")
            }
        }catch{
            write-verbose "No completions: $($_.Exception.Message)"
        }
    }
}
