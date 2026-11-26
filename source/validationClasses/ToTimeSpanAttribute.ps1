class ToTimeSpanAttribute : System.Management.Automation.ArgumentTransformationAttribute
{
    <#
        Lets time parameters take the forms people actually type, using ffmpeg's own duration rules:
          5, 2.5, '90'         seconds
          '1:30', '01:30.5'    minutes and seconds (mm:ss)
          '1:02:03'            hours, minutes and seconds (hh:mm:ss)
          a [timespan]         used as it is

        Without this, PowerShell converts 5 to a TimeSpan of 5 ticks, and '1:30' to one and a half hours.

        Usage, on a [timespan] parameter:
            [ToTimeSpan()]
            [timespan]$Start
    #>

    [object] Transform([System.Management.Automation.EngineIntrinsics]$engineIntrinsics, [object]$inputData)
    {
        $value = $inputData
        if($value -is [System.Management.Automation.PSObject])
        {
            $value = $value.BaseObject
        }
        if($null -eq $value -or $value -is [timespan])
        {
            return $value
        }
        if($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal] -or $value -is [single])
        {
            return [timespan]::FromSeconds([double]$value)
        }
        if($value -is [string])
        {
            $text = $value.Trim()
            $culture = [cultureinfo]::InvariantCulture
            $numberStyle = [System.Globalization.NumberStyles]::Float
            $seconds = 0.0
            if([double]::TryParse($text, $numberStyle, $culture, [ref]$seconds))
            {
                return [timespan]::FromSeconds($seconds)
            }
            $parts = $text.Split(':')
            if($parts.Count -in 2,3)
            {
                $hours = 0
                $minutes = 0
                $partSeconds = 0.0
                $valid = [double]::TryParse($parts[-1], $numberStyle, $culture, [ref]$partSeconds) -and [int]::TryParse($parts[-2], [ref]$minutes)
                if($parts.Count -eq 3)
                {
                    $valid = $valid -and [int]::TryParse($parts[0], [ref]$hours)
                }
                if($valid)
                {
                    return [timespan]::FromHours($hours) + [timespan]::FromMinutes($minutes) + [timespan]::FromSeconds($partSeconds)
                }
            }
        }
        throw [System.ArgumentException]::new("Cannot convert '$inputData' to a time. Use seconds (90 or 2.5), mm:ss (1:30) or hh:mm:ss (01:02:03).")
    }
}
