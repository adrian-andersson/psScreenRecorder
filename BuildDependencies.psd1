# Build dependencies for this project, in the format Install-PSResource -RequiredResourceFile reads.
# The CI templates install from this file with scripts/Install-MFBuildDependencies.ps1, so builds and tests
# use the versions pinned here rather than whatever is newest.
#
# Versions use NuGet range syntax:
#   '1.2.3'           exactly 1.2.3
#   '[1.2.3, ]'       1.2.3 or newer
#   '[1.2.3, 2.0.0)'  1.2.3 or newer, but not 2.0.0
# Add prerelease = 'true' to a module to allow its prerelease versions.
#
# Add your own module's dependencies here too, such as anything in RequiredModules, so tests can import them.
# Microsoft.PowerShell.PSResourceGet is not listed, as it installs everything else. PowerShell 7.4 and newer include it.
@{
    'ModuleForge' = @{
        version = '[1.4.1, 2.0.0)'
        repository = 'PSGallery'
    }
    'Pester' = @{
        version = '[6.0.0, 7.0.0)'
        repository = 'PSGallery'
    }
    'PSScriptAnalyzer' = @{
        version = '[1.25.0, 2.0.0)'
        repository = 'PSGallery'
    }
    'Microsoft.PowerShell.PlatyPS' = @{
        version = '[1.0.3, 2.0.0)'
        repository = 'PSGallery'
    }
}
