---
external help file: psScreenRecorder-help.xml
Module Name: psScreenRecorder
online version:
schema: 2.0.0
---

# install-ffMpeg

## SYNOPSIS
Download ffmpeg

## SYNTAX

```
install-ffMpeg [[-ffmpegUri] <String>] [[-tempPath] <String>] [[-installPath] <String>] [<CommonParameters>]
```

## DESCRIPTION
Download FFMPEG zip file
Extract to allUsersProfile folder

## EXAMPLES

### EXAMPLE 1
```
install-ffMpeg
```

## PARAMETERS

### -ffmpegUri
URI for where the zip file lives

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: Https://ffmpeg.zeranoe.com/builds/win64/static/ffmpeg-20190312-d227ed5-win64-static.zip
Accept pipeline input: False
Accept wildcard characters: False
```

### -tempPath
Path to save the zip file

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: "$($env:temp)\ffmpeg.zip"
Accept pipeline input: False
Accept wildcard characters: False
```

### -installPath
Where to extract the zip file

------------

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: "$($env:ALLUSERSPROFILE)\ffmpeg"
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable.
For more information, see about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES
Author: Adrian Andersson


Changelog:

    2019-03-14 - AA
        - Initial Script
        - Tested and working

## RELATED LINKS
