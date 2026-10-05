#!/usr/bin/env bash
# iOS simulator smoke run (#125): boots a simulator, installs the debug
# build, launches the app and verifies the process stays alive. Automates
# the "fresh install launches" slice of the real-device checklist; the
# hardware-only items stay manual.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PATH="build/ios/iphonesimulator/Runner.app"
BUNDLE_ID="com.localbluey.localBluey"
[ -d "$APP_PATH" ] || { echo "missing $APP_PATH - build first"; exit 1; }

# Newest available iPhone device type + newest iOS runtime on this runner.
DEVICE_TYPE=$(xcrun simctl list devicetypes -j \
  | jq -r '[.devicetypes[] | select(.name | startswith("iPhone"))][-1].identifier')
RUNTIME=$(xcrun simctl list runtimes -j \
  | jq -r '[.runtimes[] | select(.name | startswith("iOS"))][-1].identifier')
[ -n "$DEVICE_TYPE" ] && [ "$RUNTIME" != "null" ] || {
  echo "no iPhone device type or iOS runtime available"; exit 1; }

UDID=$(xcrun simctl create bluey-ci "$DEVICE_TYPE" "$RUNTIME")
cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
            xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 10

# Alive check: the launch prints the pid; a crash would end the process.
if ! xcrun simctl spawn "$UDID" launchctl list | grep -q "$BUNDLE_ID"; then
  echo "app is not running after launch"
  xcrun simctl spawn "$UDID" log show --last 2m --predicate \
    'process == "Runner"' --style compact | tail -30 || true
  exit 1
fi

mkdir -p build/simulator
xcrun simctl io "$UDID" screenshot build/simulator/launch.png
echo "simulator smoke OK (udid $UDID)"
