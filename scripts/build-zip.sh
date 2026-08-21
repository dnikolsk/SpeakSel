#!/usr/bin/env bash
# Build SpeakSel.app and zip it. Unsigned/ad-hoc so it can run on CI without
# a Developer ID certificate. For a notarized zip, archive in Xcode with the
# Release Developer ID identity and notarytool.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

derived="${root}/build/DerivedData"
dist="${root}/build/dist"
mkdir -p "$dist"
rm -rf "$derived"
mkdir -p "$derived"

signing=(
  CODE_SIGN_IDENTITY="-"
  CODE_SIGNING_REQUIRED=YES
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGN_STYLE=Manual
  DEVELOPMENT_TEAM=
  ENABLE_HARDENED_RUNTIME=NO
)

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  xcodebuild \
    -scheme SpeakSel \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived" \
    "${signing[@]}" \
    test
fi

xcodebuild \
  -scheme SpeakSel \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  "${signing[@]}" \
  build

app="${derived}/Build/Products/Release/SpeakSel.app"
if [[ ! -d "$app" ]]; then
  echo "error: missing $app" >&2
  find "$derived" -name 'SpeakSel.app' -type d >&2 || true
  exit 1
fi

zip_path="${dist}/SpeakSel.zip"
rm -f "$zip_path"
ditto -c -k --keepParent --sequesterRsrc "$app" "$zip_path"
echo "Built ${zip_path}"
ls -lh "$zip_path"
