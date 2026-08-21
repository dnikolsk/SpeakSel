# Releasing SpeakSel

macOS Accessibility permission is bound to the **code signature**, not the app name. 1.0.1 is Developer ID + notarized. An ad-hoc GitHub Actions zip is a different identity, so:

- Gatekeeper shows “Apple could not verify SpeakSel”
- The Accessibility switch can stay **on** while SpeakSel still reports **Required**

Installable zips must use the same **Developer ID Application** identity as 1.0.1 (team `MHCFHR9BB2`) and be notarized. Do not publish ad-hoc zips as GitHub releases.

## Local notarized zip (Mac with Xcode)

You already used this identity for 1.0.1. Store notary credentials once:

```bash
xcrun notarytool store-credentials SpeakSel \
  --apple-id YOUR_APPLE_ID \
  --team-id MHCFHR9BB2 \
  --password APP_SPECIFIC_PASSWORD
```

Then:

```bash
scripts/release.sh
```

The zip is `build/dist/SpeakSel.zip`. Replacing `/Applications/SpeakSel.app` with that zip keeps Accessibility.

## GitHub Actions (same identity on every CI zip)

Add these repository secrets (Settings → Secrets and variables → Actions):

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of a `.p12` that contains **Developer ID Application** (`MHCFHR9BB2`) |
| `DEVELOPER_ID_P12_PASSWORD` | Password for that `.p12` |
| `APPLE_API_KEY` | Full contents of the App Store Connect `.p8` key file |
| `APPLE_API_KEY_ID` | Key ID (e.g. `AB12CD34EF`) |
| `APPLE_API_ISSUER` | Issuer UUID from App Store Connect → Users and Access → Integrations |

Export the certificate on the Mac that already has it:

```bash
# Keychain Access → My Certificates → Developer ID Application → Export… (.p12)
base64 -i DeveloperID.p12 | pbcopy
```

Create an App Store Connect API key with at least **Developer** access, download the `.p8`, and paste its contents into `APPLE_API_KEY`.

After the secrets exist, push or **Run workflow**. CI notarizes and publishes `v1.0.2-pre`. Unsigned test zips stay Actions artifacts named `SpeakSel-unsigned` and are not GitHub releases.
