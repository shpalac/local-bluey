#!/usr/bin/env bash
# macOS e2e harness (#124).
#
# Bluey is a Flutter canvas, so it publishes no macOS accessibility tree and
# cannot be driven by AX-first tools (mac-use, macos-cu, mac-control-mcp) -
# they see only the window's close/minimise buttons. What does work is the same
# three primitives any Mac automation uses:
#
#   1. CGWindowListCopyWindowInfo  -> the window id + bounds
#   2. screencapture -x -o -l <id> -> a window-scoped PNG, z-order independent
#   3. CGEvent posts               -> real clicks/holds Bluey receives as gestures
#
# So this script builds those, preflights the two TCC grants macOS will not
# automate, and exposes click/hold/shot as subcommands.
#
# Usage:
#   tool/mac_e2e.sh doctor                 # report what is missing
#   tool/mac_e2e.sh shot out.png           # capture Bluey's window
#   tool/mac_e2e.sh click <x> <y>          # x/y in *screen points*
#   tool/mac_e2e.sh hold <x> <y> [secs]    # press-and-hold (hold-to-talk)
#   tool/mac_e2e.sh face                   # click the centre of the face
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${TMPDIR:-/tmp}/bluey_e2e"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------- swift helpers
# Written once and cached: swiftc startup dominates an e2e run otherwise.
build_helper() {
  local name="$1" src="$2"
  if [ ! -x "$BUILD_DIR/$name" ] || [ "$src" -nt "$BUILD_DIR/$name" ]; then
    swiftc -O "$src" -o "$BUILD_DIR/$name" 2>/dev/null
  fi
}

cat > "$BUILD_DIR/win.swift" <<'SWIFT'
import CoreGraphics
import Foundation
// Window id + bounds for the Runner window, by owner name.
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in list {
  guard (w[kCGWindowOwnerName as String] as? String) == "local_bluey" else { continue }
  let num = w[kCGWindowNumber as String] as? Int ?? 0
  let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let x = (b["X"] as? Double) ?? 0, y = (b["Y"] as? Double) ?? 0
  let ww = (b["Width"] as? Double) ?? 0, hh = (b["Height"] as? Double) ?? 0
  print("\(num) \(Int(x)) \(Int(y)) \(Int(ww)) \(Int(hh))")
  exit(0)
}
exit(2)
SWIFT

cat > "$BUILD_DIR/evt.swift" <<'SWIFT'
import CoreGraphics
import Foundation
// argv: mode(move|down|up) x y
let mode = CommandLine.arguments[1]
let p = CGPoint(x: Double(CommandLine.arguments[2])!, y: Double(CommandLine.arguments[3])!)
let src = CGEventSource(stateID: .hidSystemState)
func post(_ t: CGEventType, _ clickState: Int32 = 0) {
  guard let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left) else { return }
  if clickState > 0 { e.setIntegerValueField(.mouseEventClickState, value: clickState) }
  e.post(tap: .cghidEventTap)
}
switch mode {
case "move": post(.mouseMoved)
case "down": post(.leftMouseDown, 1)
case "up":   post(.leftMouseUp, 1)
default: exit(2)
}
SWIFT

win_info() { build_helper win "$BUILD_DIR/win.swift"; "$BUILD_DIR/win"; }

# ---------------------------------------------------------------- preflight
# TCC refuses to be scripted: only a human click in System Settings can grant
# these. Everything below is a *report*, never an attempt to self-approve.
doctor() {
  local missing=0
  echo "Bluey macOS e2e preflight"
  echo

  # The process is named local_bluey (PRODUCT_NAME), not the bundle id.
  if pgrep -x local_bluey >/dev/null 2>&1; then
    echo "  ok    app running (pid $(pgrep -x local_bluey | head -1))"
  else
    echo "  MISS  app not running - 'flutter run -d macos' or: open $PWD/build/macos/Build/Products/Debug/local_bluey.app"
    missing=1
  fi

  local win
  if win=$(win_info 2>/dev/null); then
    echo "  ok    window id $win  (id x y w h)"
  else
    echo "  MISS  no on-screen Runner window"
    missing=1
  fi

  # Accessibility for the *shell*: without it every CGEvent post is dropped,
  # which looks exactly like "the app ignored my click".
  if osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null | grep -q true; then
    echo "  ok    this shell has Accessibility (CGEvent posts will land)"
  else
    echo "  MISS  this shell lacks Accessibility - grant the terminal in"
    echo "        System Settings > Privacy & Security > Accessibility"
    missing=1
  fi

  # Bluey's own grants. isTrusted() is AXIsProcessTrusted() in
  # macos/Runner/ComputerControl.swift; mic mirrors its AVFoundation check.
  if bluey_grants; then
    echo "  ok    Bluey holds Accessibility + Microphone"
  else
    echo "  MISS  Bluey is missing TCC grants (its own banner says so)."
    echo "        Grant 'local_bluey' under BOTH:"
    echo "          System Settings > Privacy & Security > Microphone"
    echo "          System Settings > Privacy & Security > Accessibility"
    echo "        Until then hold-to-talk cannot record, so the voice path"
    echo "        is untestable - every other check still runs."
    missing=1
  fi

  # Keychain: an adhoc-signed build has no TeamIdentifier, so every secure
  # write fails -34018 and Settings.save() aborts, losing all other fields.
  # Signing is configured in the gitignored Runner/Configs/Local.xcconfig.
  if [ -d build/macos/Build/Products/Debug/local_bluey.app ]; then
    if codesign -dv build/macos/Build/Products/Debug/local_bluey.app 2>&1 \
        | grep -q "TeamIdentifier=[0-9A-F]"; then
      echo "  ok    build is team-signed (settings can save to the Keychain)"
    else
      echo "  STALE build is adhoc - Settings saves will fail with -34018."
      echo "        Set DEVELOPMENT_TEAM + CODE_SIGN_IDENTITY in"
      echo "        macos/Runner/Configs/Local.xcconfig (see AppInfo.xcconfig),"
      echo "        then: flutter build macos --debug"
      missing=1
    fi
  fi

  echo
  [ "$missing" -eq 0 ] && echo "ready." || echo "not ready - see MISS above."
  return "$missing"
}

# Bluey's own grants, read through its own window: the permission banner is
# the app telling us the truth, and unlike TCC.db (SIP-protected) we can read
# the screen. Exit 0 = banners clear = grants held.
bluey_grants() {
  local id
  id=$(win_info 2>/dev/null | cut -d' ' -f1) || return 1
  screencapture -x -o -l "$id" "$BUILD_DIR/grants.png" 2>/dev/null || return 1
  # Both banners sit in the bottom band as light text on a dark bar. Bright
  # pixels there mean a banner is up, i.e. a grant is still missing.
  python3 - "$BUILD_DIR/grants.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
w, h = im.size
band = im.crop((0, int(h * 0.86), w, h))
bright = sum(1 for p in band.get_flattened_data() if p > 150)
sys.exit(1 if bright > 400 else 0)
PY
}

# ---------------------------------------------------------------- actions
shot() { local out="${1:-$BUILD_DIR/shot.png}"
  local id; id=$(win_info | cut -d' ' -f1)
  screencapture -x -o -l "$id" "$out"; echo "$out"; }

# Screen points -> absolute CGEvent coords. Callers pass what they read off a
# capture, so convert Retina pixels back to points first.
click() { build_helper evt "$BUILD_DIR/evt.swift"
  "$BUILD_DIR/evt" move "$1" "$2"; sleep 0.04
  "$BUILD_DIR/evt" down "$1" "$2"; sleep 0.06
  "$BUILD_DIR/evt" up   "$1" "$2"; }

hold() { build_helper evt "$BUILD_DIR/evt.swift"
  local secs="${3:-4}"
  "$BUILD_DIR/evt" move "$1" "$2"; sleep 0.04
  "$BUILD_DIR/evt" down "$1" "$2"; sleep "$secs"
  "$BUILD_DIR/evt" up   "$1" "$2"; }

# Centre of the face, derived from the live window bounds rather than
# hardcoded - the window moves between runs.
face() { local w; w=$(win_info)
  echo "$(( $(echo "$w" | cut -d' ' -f2) + $(echo "$w" | cut -d' ' -f4) / 2 )) \
        $(( $(echo "$w" | cut -d' ' -f3) + $(echo "$w" | cut -d' ' -f5) / 2 ))"; }

case "${1:-doctor}" in
  doctor)      doctor ;;
  shot)        shot "${2:-}" ;;
  click)       click "$2" "$3" ;;
  hold)        hold "$2" "$3" "${4:-4}" ;;
  face)        face ;;
  win)         win_info ;;
  *) echo "unknown subcommand: $1" >&2; exit 2 ;;
esac