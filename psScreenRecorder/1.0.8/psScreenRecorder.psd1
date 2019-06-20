@{
  ModuleVersion = '1.0.8'
  RootModule = 'psScreenRecorder.psm1'
  AliasesToExport = @()
  FunctionsToExport = @('convert-mp4togif','install-ffMpeg','new-psScreenRecord')
  CmdletsToExport = @()
  PowerShellVersion = '5.0.0.0'
  PrivateData = @{
    builtBy = 'Adrian.Andersson'
    moduleRevision = '1.0.7.9'
    builtOn = '2019-06-20T15:48:18'
    PSData = @{
      ReleaseNotes = 'Better usability and a few more features'
      ProjectUri = 'https://github.com/adrian-andersson/psScreenRecorder'
      IconUri = 'https://github.com/adrian-andersson/psScreenRecorder/blob/master/icon.png'
    }
    bartenderCopyright = '2019 Domain Group'
    pester = @{
      time = '00:00:04.6606869'
      codecoverage = 0
      passed = '100 %'
    }
    bartenderVersion = '6.1.22'
    moduleCompiledBy = 'Bartender | A Framework for making PowerShell Modules'
  }
  GUID = '66b95cf8-97e8-4448-8015-38d0e35456a0'
  Description = 'Desktop Video Capture with PowerShell'
  Copyright = '2019 Adrian Andersson'
  CompanyName = 'Adrian Andersson'
  Author = 'Adrian.Andersson'
  ScriptsToProcess = @()
}
