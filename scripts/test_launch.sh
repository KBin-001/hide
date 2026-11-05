#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun simctl list devices available --json > build/simulators.json
device_id="$(python3 - <<'PY'
import json
with open('build/simulators.json') as f:
    devices = json.load(f)['devices']
for runtime, items in sorted(devices.items(), reverse=True):
    if 'iOS' not in runtime:
        continue
    for device in items:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit('No available iPhone simulator runtime')
PY
)"
xcrun simctl boot "$device_id" || true
xcrun simctl bootstatus "$device_id" -b
trap 'xcrun xcresulttool export attachments --path build/ui-results.xcresult --output-path build/ui-attachments || true' EXIT
xcodebuild test -project Calculator.xcodeproj -scheme Calculator \
  -destination "platform=iOS Simulator,id=$device_id" -parallel-testing-enabled NO \
  -derivedDataPath build/UITestDerivedData -resultBundlePath build/ui-results.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
