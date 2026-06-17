# Agent Startup — Release Mode

You are starting a release session for the **fleetmap** project. Work autonomously through every step. Only stop to confirm the final release action before pushing the tag.

fleetmap ships as a downloadable macOS app. You do **not** build anything locally: you bump the version, push an annotated tag, and the `.github/workflows/release.yml` GitHub Action builds, signs, **notarizes**, and publishes the DMG to the GitHub release. The version source of truth is `app/Resources/Info.plist`.

## 1. Load Context

Read silently:
- `app/Resources/Info.plist` — current `CFBundleShortVersionString` (semver) and `CFBundleVersion` (build number)
- `.github/workflows/release.yml` — confirm the tag trigger and asset name (`FleetMap-<version>.dmg`)

## 2. Assess Current State

Run:
- `git status` — must be on `main` with a clean working tree. If not, stop and report.
- `git fetch origin && git log origin/main --oneline -5` — confirm local `main` is up to date with remote.
- Confirm the required release secrets are configured: `gh secret list --repo georgenijo/fleetmap`. The set must include `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `SIGNING_IDENTITY`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`, `AC_API_KEY_P8_BASE64`. If any are missing, stop and point the user to `RELEASING.md` — the build will fail at the signing/notarization step without them.

## 3. Determine Version Bump

Run:
- `git tag --sort=-version:refname | head -5` — find the last release tag (format `v<major>.<minor>.<patch>`). If there are no tags yet, this is the first release; use the version already in `Info.plist` (currently `0.1.0`) as the starting point and do not bump it.
- `git log {last_tag}..HEAD --oneline` — all commits since that tag
- `git diff {last_tag}..HEAD --stat` — files changed

Analyse the commits using these rules (in priority order):
- Any commit with `feat!:`, `BREAKING CHANGE`, or a major architectural change → **major bump**
- Any commit with `feat:` → **minor bump**
- Only `fix:`, `chore:`, `docs:`, `refactor:`, `test:` → **patch bump**

While in `0.x` (alpha), keep breaking changes as **minor** bumps unless the user says otherwise.

Determine the new version by applying the bump to the current `CFBundleShortVersionString`.

## 4. Summarise and Confirm

Present a concise release summary:
- Current version → New version (and why: major/minor/patch)
- Bullet list of what's included since the last tag (one line per meaningful commit, skip pure chores/docs)
- The DMG that CI will publish: `FleetMap-{new_version}.dmg` (signed + notarized)
- Ask: **"Ready to release v{new_version}? Confirm to proceed."**

Stop and wait for confirmation.

## 5. Execute Release

On confirmation, run these steps in order:

1. Bump the version in `app/Resources/Info.plist`:
   - `/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString {new_version}" app/Resources/Info.plist`
   - Increment the build number: `/usr/libexec/PlistBuddy -c "Set :CFBundleVersion {current_build + 1}" app/Resources/Info.plist`
2. Commit: `git add app/Resources/Info.plist && git commit -m "chore: release v{new_version}"`
3. Push: `git push origin main`
4. Write the release notes to a temp file (user-facing language, not raw commit messages), then create an **annotated** tag from it so CI can publish them via `--notes-from-tag`:
   ```bash
   cat > /tmp/fleetmap-notes.md <<'EOF'
   ## What's New
   - bullet per meaningful `feat:` commit

   ## Improvements
   - bullet per `perf:` / `refactor:` commit (omit section if none)

   ## Fixes
   - bullet per `fix:` commit (omit section if none)

   ## Install
   Download `FleetMap-{new_version}.dmg` below, open it, and drag **FleetMap** to Applications.

   ## Full Changelog
   https://github.com/georgenijo/fleetmap/compare/v{previous_version}...v{new_version}
   EOF
   git tag -a v{new_version} -F /tmp/fleetmap-notes.md
   ```
   Omit any section that has no entries. For the first release, drop the compare link.
5. Push the tag — this triggers the build: `git push origin v{new_version}`

## 6. Hand Off

Tell the user:
- Tag pushed — GitHub Actions is now building the signed, **notarized** DMG (~10–20 min on a macOS runner).
- Where to watch: `https://github.com/georgenijo/fleetmap/actions`
- Release will publish automatically at: `https://github.com/georgenijo/fleetmap/releases/tag/v{new_version}`
- Once green, the DMG opens cleanly with no Gatekeeper warning. If the run fails at the notarize step, the most likely cause is a missing/expired secret — check `RELEASING.md`.
