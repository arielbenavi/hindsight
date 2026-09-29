# hindsight — iOS

The iOS app (SwiftUI, Swift 6, iOS 26+).

## Requirement: XcodeGen

**You need [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build or work on this app.** The Xcode project (`Hindsight.xcodeproj`) is **not in git**. It's generated from [`project.yml`](project.yml), so after cloning there's nothing to open until you generate it.

Why: Xcode's project file (`project.pbxproj`) is a machine-written list of every file with random IDs. When two people add files on different branches, git conflicts on it constantly, and the conflicts can't be read. `project.yml` is short and hand-written, and it includes whole folders instead of listing files. Adding a Swift file doesn't change it, so there's nothing to conflict.

## Setup (once)

```bash
brew install xcodegen
```

## Open the project

```bash
cd ios
xcodegen
open Hindsight.xcodeproj
```

Run `xcodegen` again whenever:
- you pull changes that touch `project.yml`
- you edit `project.yml` yourself

## Rules

- **Add files by creating them in the right folder** (e.g. `Hindsight/`). They're included automatically. No need to touch `project.yml`.
- **Change project settings in `project.yml`, never in Xcode's settings UI.** This covers targets, capabilities, build settings, the bundle ID, and Info.plist keys. Changes made in the Xcode UI only live in the generated project and are wiped the next time anyone runs `xcodegen`.
- **Never commit `Hindsight.xcodeproj`.** It's in `.gitignore`.

## Layout

```
project.yml         project definition (source of truth)
Hindsight/          app source
  Models/           SavedPost + Platform (canonical data format)
  Import/           parser (Muse JSON + seed markdown) and SavedPostStore
  Onboarding/       first-run flow; OnboardingStyle.swift holds all its styling
  Sync/             Muse sync prototype
  Resources/        asset catalog
HindsightTests/     unit tests (Swift Testing)
```

The seed export [`../data/ig-saved-posts-seed.md`](../data/ig-saved-posts-seed.md) is bundled into the app via `project.yml`. That gives the app real saved-post data to build against. `SeedData.swift` loads it and `SavedPostParser` turns it into `SavedPost`s.

Launch with the `-resetOnboarding` argument (Scheme → Run → Arguments) to replay the first-run flow.

## Build & test from the command line

```bash
xcodebuild test -project Hindsight.xcodeproj -scheme Hindsight -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Signing

Signing uses Reut's Apple Developer team (`DEVELOPMENT_TEAM` in `project.yml`).
- **Simulator:** no signing needed.
- **A real device or TestFlight:** you need to be a member of that team.
