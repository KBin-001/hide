#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun simctl list devices available --json > build/simulators.json
device_id="$(python3 - <<'PY'
import json, subprocess
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
compatible = 'iOS-' + sdk.replace('.', '-')
with open('build/simulators.json') as f:
    devices = json.load(f)['devices']
for runtime, items in sorted(devices.items(), reverse=True):
    if not runtime.endswith(compatible):
        continue
    for device in items:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit('No iPhone simulator matching Xcode SDK ' + sdk)
PY
)"
xcrun simctl boot "$device_id" || true
xcrun simctl bootstatus "$device_id" -b
trap 'xcrun xcresulttool export attachments --path build/ui-results.xcresult --output-path build/ui-attachments || true' EXIT
set +e
xcodebuild test -project Calculator.xcodeproj -scheme Calculator \
  -destination "platform=iOS Simulator,id=$device_id" -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 150 \
  -derivedDataPath build/UITestDerivedData -resultBundlePath build/ui-results.xcresult \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- 2>&1 | tee build/ui-build.log
build_status=${PIPESTATUS[0]}
set -e
if [ "$build_status" -ne 0 ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    printf '## iOS build / UI test failure\n\n```text\n'
    python3 - <<'SUMMARY'
from pathlib import Path
import sys
lines = Path('build/ui-build.log').read_text(errors='replace').splitlines()
keywords = ('error:', 'Assertion Failure', 'failed', 'unable to type-check', 'Testing cancelled', 'timed out', 'Time limit')
selected = [line for line in lines if any(word in line for word in keywords)]
print('\n'.join((selected or lines)[-60:]))
precise = [line for line in lines if 'error:' in line.lower() or 'Assertion Failure' in line]
for line in (precise or selected)[-10:]:
    escaped = line.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print('::error title=iOS build or UI test failure::' + escaped, file=sys.stderr)
SUMMARY
    printf '\n```\n'
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$build_status"
