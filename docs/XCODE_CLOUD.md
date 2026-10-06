# Xcode Cloud: a TestFlight build on every push

Goal: every push to `master` builds hindsight in Apple's cloud and puts it on TestFlight (about 30 min). Nobody's Mac is involved, and Apple signs the build, so Ariel doesn't need signing rights on Reut's team.

**Has to be done by Reut** (owner of the Apple Developer account, team HE6MENN8S6). About 10 minutes. Free up to 25 compute hours/month.

## Already in the repo
- `ios/ci_scripts/ci_post_clone.sh`: installs XcodeGen and generates `Hindsight.xcodeproj` (it isn't in git). Xcode Cloud runs it automatically after cloning.

## Steps (Reut, once)
1. `git pull`, then `cd ios && xcodegen && open Hindsight.xcodeproj`.
2. In Xcode: **Product → Xcode Cloud → Create Workflow…** → pick the **Hindsight** app → sign in / grant access to the GitHub repo `arielbenavi/hindsight` when asked.
3. Edit the workflow:
   - **Start condition:** Branch Changes → `master`.
   - **Actions:** Archive (iOS), **Distribution preparation: TestFlight (Internal Testing Only)**.
   - **Post-actions:** TestFlight Internal Testing → add the tester group with Ariel.
4. Save. The first build starts; check it in **App Store Connect → Xcode Cloud** (or Xcode's Report navigator).
5. If the build number must increase: in the workflow's Archive action, Xcode Cloud sets `CI_BUILD_NUMBER`. Either set `CURRENT_PROJECT_VERSION: $(CI_BUILD_NUMBER)` in `project.yml`, or turn on "Automatically manage build numbers" in App Store Connect.

## Notes
- Builds use Apple's newest Xcode by default, the same as Reut's. If Ariel's older Xcode 26.3 matters, pin the version in the workflow's Environment.
- Feature branches don't build unless you add a start condition for them (e.g. pull requests).
- To stop it: disable the workflow in App Store Connect → Xcode Cloud.
