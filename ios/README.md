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
  Models/           SavedPost + Platform (the canonical data format)
  Import/           SavedPostParser (Muse JSON + seed markdown), SavedPostStore,
                    DataExportParser + ZipReader (IG/FB/TikTok "download your data")
  Onboarding/       first-run flow; OnboardingStyle.swift holds all its styling
  Sync/             syncing sources: SourceCards (shared by onboarding + SourcesView),
                    Muse (MuseSyncView, MuseConnector, MusePrompt, MuseLauncher),
                    WhatsApp (WhatsAppImportView, WhatsAppGuide animation),
                    ServerSync (pull from the connector), WhatsAppBot
    X/              Connect X: PKCE sign-in, Keychain tokens, bookmarks client
ci_scripts/         Xcode Cloud: generates the project with xcodegen (docs/XCODE_CLOUD.md)
  DebugLog.swift    DEBUG-only event log for device testing
  Resources/        asset catalog
scripts/device.sh   install on / pull logs from a connected iPhone
HindsightTests/     unit tests (Swift Testing)
```

The seed export [`../data/ig-saved-posts-seed.md`](../data/ig-saved-posts-seed.md) is bundled into the app via `project.yml`. That gives the app real saved-post data to build against. `SeedData.swift` loads it and `SavedPostParser` turns it into `SavedPost`s.

Launch with the `-resetOnboarding` argument (Scheme → Run → Arguments) to replay the first-run flow.

## Testing on a real iPhone

`scripts/device.sh` builds, installs and launches on a connected iPhone, and pulls the app's debug log:

```bash
scripts/device.sh install
scripts/device.sh log
```

- The phone needs Developer Mode on (Settings → Privacy & Security). The first launch of a new signer needs Settings → General → VPN & Device Management → Trust.
- Signing uses `project.yml`'s team. If your role on that team can't create certificates (for example "App Manager" without "Access to Certificates, Identifiers & Profiles"), use your free Personal Team and your own bundle ID without touching `project.yml`:
  `HINDSIGHT_TEAM=<your team id> HINDSIGHT_BUNDLE_ID=com.you.hindsight scripts/device.sh install`
  Personal Team builds expire after 7 days.
- DEBUG builds append events (Muse link attempts, pastes, X sync) to `Library/Application Support/debug-log.txt`, which is what `log` prints.
- To replay onboarding: launch with `-resetOnboarding`, e.g. `xcrun devicectl device process launch --device <id> --terminate-existing <bundle id> -- -resetOnboarding`.

## Build & test from the command line

```bash
xcodebuild test -project Hindsight.xcodeproj -scheme Hindsight -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Signing

Signing uses Reut's Apple Developer team (`DEVELOPMENT_TEAM` in `project.yml`).
- **Simulator:** no signing needed.
- **A real device or TestFlight:** you need to be a member of that team.
