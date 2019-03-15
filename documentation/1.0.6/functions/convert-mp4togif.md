---
external help file: psScreenRecorder-help.xml
Module Name: psScreenRecorder
online version:
schema: 2.0.0
---

# convert-mp4togif

## SYNOPSIS
Use FFMPEG to convert an mp4 to a gif

## SYNTAX

```
convert-mp4togif [-mp4Path] <String> [-gifPath] <String> [-ffMPegPath <String>] [-tempPath <String>]
 [-fps <Int32>] [<CommonParameters>]
```

## DESCRIPTION
Use FFMPEG to convert an mp4 to a gif

## EXAMPLES

### EXAMPLE 1
```
convert-mp4togif -mp4Path c:\input.mp4 -gifPath c:\output.gif
```

## PARAMETERS

### -mp4Path
path to the mp4File

```yaml
Type: String
Parameter Sets: (All)
Aliases: path

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -gifPath
path to export the gif file

```yaml
Type: String
Parameter Sets: (All)
Aliases: destination

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ffMPegPath
Path to ffMpeg
      Suggest you modify this to be where yours is by default

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $(get-childitem -path "$($env:ALLUSERSPROFILE)\ffmpeg" -filter 'ffmpeg.exe' -Recurse|sort-object -Property LastWriteTime -Descending|select-object -First 1).fullname
Accept pipeline input: False
Accept wildcard characters: False
```

### -tempPath
Where to keep the palette file

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: "$($env:temp)\ffmpeg"
Accept pipeline input: False
Accept wildcard characters: False
```

### -fps
The FPS to use for the gif

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 5
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
      		
      Changelog
      
          13-09-2019 - AA
              - Initial Script

## RELATED LINKS
