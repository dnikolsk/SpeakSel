#!/usr/bin/env bash
# Archive, Developer ID sign, notarize, staple, and zip SpeakSel.app.
# Same signing identity as 1.0.1 so Gatekeeper and Accessibility survive updates.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

team="${DEVELOPMENT_TEAM:-MHCFHR9BB2}"
profile="${NOTARY_KEYCHAIN_PROFILE:-SpeakSel}"
build_dir="${root}/build"
archive_path="${build_dir}/SpeakSel.xcarchive"
export_dir="${build_dir}/export"
dist="${build_dir}/dist"
app="${export_dir}/SpeakSel.app"
zip_path="${dist}/SpeakSel.zip"
identity="${CODE_SIGN_IDENTITY:-Developer ID Application}"

mkdir -p "$dist" "$export_dir"
rm -rf "$archive_path" "$export_dir"
mkdir -p "$export_dir"

echo "Archiving with ${identity} (team ${team})…"
xcodebuild \
  -scheme SpeakSel \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_IDENTITY="$identity" \
  CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES \
  archive

echo "Exporting…"
xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_dir" \
  -exportOptionsPlist "${root}/scripts/exportOptions-developer-id.plist"

if [[ ! -d "$app" ]]; then
  echo "error: missing $app" >&2
  ls -la "$export_dir" >&2 || true
  exit 1
fi

echo "Signing check…"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv --verbose=4 "$app" 2>&1 | grep -E 'Authority=Developer ID Application|TeamIdentifier=' 

rm -f "$zip_path"
ditto -c -k --keepParent --sequesterRsrc "$app" "$zip_path"

echo "Submitting to notary service…"
if [[ -n "${APPLE_API_KEY_PATH:-}" ]]; then
  xcrun notarytool submit "$zip_path" \
    --key "$APPLE_API_KEY_PATH" \
    --key-id "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is required}" \
    --issuer "${APPLE_API_ISSUER:?APPLE_API_ISSUER is required}" \
    --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$zip_path" \
    --apple-id "$APPLE_ID" \
    --team-id "$team" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
else
  xcrun notarytool submit "$zip_path" --keychain-profile "$profile" --wait
fi

echo "Stapling…"
xcrun stapler staple "$app"
xcrun stapler validate "$app"

rm -f "$zip_path"
ditto -c -k --keepParent --sequesterRsrc "$app" "$zip_path"
echo "Notarized zip: ${zip_path}"
ls -lh "$zip_path"
