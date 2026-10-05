#!/usr/bin/env bash
# iOS simulator smoke run (#125): boots a simulator, installs the debug
# build, launches the app and verifies the process stays alive. Automates
# the "fresh install launches" slice of the real-device checklist; the
# hardware-only items stay manual.
set -euo pipefail
set -x
cd "$(dirname "$0")/.."

APP_PATH="build/ios/iphonesimulator/Runner.app"
BUNDLE_ID="com.localbluey.localBluey"
[ -d "$APP_PATH" ] || { echo "missing $APP_PATH - build first"; exit 1; }

# Use a device the runner image already ships: the newest iOS runtime's
# newest available iPhone. Creating a fresh device from the newest device
# type fails with "Incompatible device" when it needs a newer runtime.
UDID=$(xcrun simctl list devices available -j | jq -r '
  [.devices | to_entries[] | select(.key | test("iOS")) | select(.value | length > 0)]
  | sort_by(.key | capture("iOS-(?<v>[0-9-]+)").v | split("-") | map(tonumber))
  | last | .value | map(select(.name | startswith("iPhone"))) | last | .udid')
[ -n "$UDID" ] && [ "$UDID" != "null" ] || {
  echo "no available iPhone simulator on this runner"
  xcrun simctl list devices available; exit 1; }
echo "using simulator $UDID"
cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
            true; }
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
