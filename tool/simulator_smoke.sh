#!/usr/bin/env bash
# iOS simulator smoke run (#125): boots a simulator, installs the debug
# build, launches the app and verifies the process stays alive. Automates
# the "fresh install launches" slice of the real-device checklist; the
# hardware-only items stay manual.
set -euo pipefail
set -x
cd "$(dirname "$0")/.."

# Usage: simulator_smoke.sh [preboot]
#   preboot  only start booting the simulator and return. First-boot data
#            migration on a cold runner can take 4+ minutes, so CI runs this
#            before the iOS build and lets the two overlap.
MODE="${1:-run}"
APP_PATH="build/ios/iphonesimulator/Runner.app"
BUNDLE_ID="com.localbluey.localBluey"
if [ "$MODE" != "preboot" ]; then
  [ -d "$APP_PATH" ] || { echo "missing $APP_PATH - build first"; exit 1; }
fi

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
if [ "$MODE" = "preboot" ]; then
  # Idempotent: the run phase boots again and tolerates an already-booted device.
  xcrun simctl boot "$UDID" || true
  exit 0
fi
cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
            true; }
trap cleanup EXIT

phase_start=$SECONDS
xcrun simctl boot "$UDID" || true   # already booted if preboot ran
xcrun simctl bootstatus "$UDID" -b
echo "boot wait: $((SECONDS - phase_start))s"
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 10

# Alive check: the launch prints the pid; a crash would end the process.
# Capture first: `grep -q` exits early, launchctl then dies with SIGPIPE and
# pipefail reports a false failure.
LAUNCHD_LIST=$(xcrun simctl spawn "$UDID" launchctl list)
if ! grep -q "$BUNDLE_ID" <<<"$LAUNCHD_LIST"; then
  echo "app is not running after launch"
  xcrun simctl spawn "$UDID" log show --last 2m --predicate \
    'process == "Runner"' --style compact | tail -30 || true
  exit 1
fi

mkdir -p build/simulator
xcrun simctl io "$UDID" screenshot build/simulator/launch.png
echo "simulator smoke OK (udid $UDID)"
