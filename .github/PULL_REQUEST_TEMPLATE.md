## Notes for reviewers, related issues and change IDs

<!-- Anything the commits don't say: why, context, how you tested it, or where to look closely.
     "Fixes #123" closes the issue when this merges -->

## Checklist

- [ ] Commits use changelog prefixes (`feat:`, `fix:` ...). `Get-MFGitPrefixHelp` lists them
- [ ] New or changed behaviour has Pester tests

## Type of change

<!-- Tick all that apply. The highest-impact one guides the Release choice. Get-MFGitPrefixHelp has the details -->

- [ ] 🔴 Breaking: could break callers. Mandatory, renamed or removed parameters, changed defaults or output
- [ ] 🟡 Feature: something new. Functions, optional parameters, more output
- [ ] 🟢 Fix: something broken now works. Bugs, stream messages, performance
- [ ] ⚪ Non-module change: docs, CI/CD, tests

## Release

<!-- The Build and Release choice to run after this merges -->

- [ ] **Next Prerelease**: most pull requests
- [ ] **New Prerelease Series: minor**: the first feature since the last stable release
- [ ] **New Prerelease Series: major**: the first breaking change since the last stable release
- [ ] **No build yet**: more pull requests to come first
- [ ] **Promote to Stable**: the last pull request in the series, once its prerelease is tested

<!-- ModuleForge's pull request template. Adapt it to your project, or replace it -->
