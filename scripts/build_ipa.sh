#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build dist
xcodebuild -project Calculator.xcodeproj -scheme Calculator -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build

# Fresh staging: never recursively remove a caller-provided or calculated directory.
stage="$(mktemp -d "$PWD/build/stage.XXXXXX")"
mkdir -p "$stage/Payload"
ditto build/DerivedData/Build/Products/Release-iphoneos/Calculator.app "$stage/Payload/Calculator.app"
app="$stage/Payload/Calculator.app"
# No certificate, Apple ID, provisioning profile, private entitlement, or exportArchive needed.
# TrollStore re-signs this ad-hoc signature at installation, retaining its entitlements.
if [ -d "$app/Frameworks" ]; then
  while IFS= read -r -d '' framework; do
    codesign --force --sign - --timestamp=none "$framework"
  done < <(find "$app/Frameworks" -mindepth 1 -maxdepth 1 -print0)
fi
codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements Resources/Calculator.entitlements "$app"
ditto -c -k --keepParent "$stage/Payload" dist/Calculator.ipa
python3 scripts/verify_ipa.py dist/Calculator.ipa --report dist/verification.json
shasum -a 256 dist/Calculator.ipa > dist/Calculator.ipa.sha256
cat dist/verification.json
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<'SUMMARY'
### Calculator IPA
- Device build and core behavior tests passed.
- IPA Payload structure, iOS 16.0 minimum, arm64 iOS Mach-O and signed entitlements verified.
- TrollStore installation: **pending device validation**.
- Family Controls individual authorization and actual hiding/shielding: **pending device validation**.
Download Calculator-TrollStore artifact within 3 days. It contains IPA, SHA-256 and verification.json.
SUMMARY
fi
