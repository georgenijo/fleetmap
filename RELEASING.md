# Releasing fleetmap

Releases are automated. To cut one:

```sh
release        # zsh function → runs the agent in prompts/PROMPT_RELEASE.md
```

The agent bumps the version in `app/Resources/Info.plist`, pushes an annotated
`vX.Y.Z` tag, and the [`release` workflow](.github/workflows/release.yml) builds,
signs, **notarizes**, and publishes a `FleetMap-X.Y.Z.dmg` to the GitHub release.
A notarized + stapled DMG opens cleanly — no "unidentified developer" or
"damaged" Gatekeeper warning.

---

## One-time setup (Apple side + GitHub secrets)

These steps can't be automated — they involve your Apple Developer account and
secret material. Do them once.

### 1. Developer ID Application certificate

In **Xcode → Settings → Accounts → (your team) → Manage Certificates →  + →
Developer ID Application**. Then export it as a `.p12`:

- **Keychain Access → My Certificates**, find *Developer ID Application: …*,
  right-click → **Export**, save as `DeveloperID.p12`, set a strong password.

Note the full identity name (used as `SIGNING_IDENTITY`):

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
# → "Developer ID Application: George Nijo (TEAMID)"
```

### 2. App Store Connect API key (for notarytool)

**App Store Connect → Users and Access → Integrations → App Store Connect API →
Generate API Key**. Role **Developer** is sufficient for notarization.

- Download the `AuthKey_XXXXXXXX.p8` (**one-time download** — save it).
- Note the **Key ID** and the team's **Issuer ID** (shown on that page).

### 3. Add the GitHub repository secrets

From the repo root (`gh` already authed as `georgenijo`):

```sh
base64 -i DeveloperID.p12        | gh secret set BUILD_CERTIFICATE_BASE64 --repo georgenijo/fleetmap
echo -n 'YOUR_P12_PASSWORD'      | gh secret set P12_PASSWORD             --repo georgenijo/fleetmap
echo -n "$(openssl rand -hex 16)"| gh secret set KEYCHAIN_PASSWORD        --repo georgenijo/fleetmap
echo -n 'Developer ID Application: George Nijo (TEAMID)' \
                                 | gh secret set SIGNING_IDENTITY         --repo georgenijo/fleetmap

echo -n 'YOUR_KEY_ID'            | gh secret set AC_API_KEY_ID            --repo georgenijo/fleetmap
echo -n 'YOUR_ISSUER_ID'         | gh secret set AC_API_ISSUER_ID         --repo georgenijo/fleetmap
base64 -i AuthKey_XXXXXXXX.p8    | gh secret set AC_API_KEY_P8_BASE64     --repo georgenijo/fleetmap
```

Verify: `gh secret list --repo georgenijo/fleetmap` should show all seven.

> Delete the local `DeveloperID.p12` and `.p8` from disk once the secrets are set
> (or store them in your password manager). They are no longer needed locally.

---

## Building locally (no signing)

```sh
cd app
./scripts/bundle.sh release          # ad-hoc signed FleetMap.app (local use only)
./scripts/make-dmg.sh 0.1.0          # FleetMap-0.1.0.dmg (unsigned — not for distribution)
```

A locally built DMG is **ad-hoc signed** and will trip Gatekeeper on other Macs.
Only the CI-produced DMG is notarized and safe to hand out.

## Notes

- Runner is `macos-15` (Xcode 16 / Swift 6, required by `Package.swift`).
- The app uses the **hardened runtime** with no special entitlements — it reads
  process info via `libproc`, which needs no notarization exception, and it is
  deliberately **not** App-Sandboxed (the sandbox would block cross-process
  inspection).
- To also ship the Go CLI as a release asset, uncomment the final block in
  `.github/workflows/release.yml`.
