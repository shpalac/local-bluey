import AVFoundation
import Cocoa
import FlutterMacOS

/// Flutter MethodChannel bridging the ported vision + control layer
/// (ScreenReader, ControlsReader, ComputerControl) to Dart.
final class NativeControlChannel {
  static let name = "local_bluey/control"

  /// The last captured snapshot, so target ids from look_at_screen stay
  /// resolvable for point_at / click without another capture.
  private static var lastSnapshot: ScreenSnapshot?

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]

      func point() -> CGPoint? {
        guard let x = args["x"] as? Double, let y = args["y"] as? Double else { return nil }
        return CGPoint(x: x, y: y)
      }

      switch call.method {
      case "isTrusted":
        result(ComputerControl.isTrusted)
      case "screenCaptureAccess":
        // Preflight only - never prompts (#174): the request itself stays
        // lazy, fired by the feature that needs it.
        result(CGPreflightScreenCaptureAccess())
      case "requestScreenCaptureAccess":
        // macOS only lists an app under Privacy & Security > Screen Recording
        // once it has actually *asked*; preflight never registers it. Without
        // this, the recovery card's "Fix" deep-link landed on a pane where
        // Bluey was absent, so there was nothing for the user to switch on
        // (#124). Safe to call because it only ever runs from an explicit tap
        // on that card - the same consent the system prompt asks about.
        result(CGRequestScreenCaptureAccess())
      case "microphoneAccess":
        result(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
      case "askPermission":
        ComputerControl.askForPermission()
        result(nil)
      case "openAccessibilitySettings":
        ComputerControl.openAccessibilitySettings()
        result(nil)
      case "watchFrontmostInfo":
        // Cheap watcher signal poll (#213): front app, window title, lock.
        result(WatchSignals.frontmostInfo())
      case "mouseLocation":
        let p = ComputerControl.mouseLocation
        result(["x": Double(p.x), "y": Double(p.y)])
      case "warp":
        guard let p = point() else { result(FlutterError(code: "args", message: "x,y required", details: nil)); return }
        ComputerControl.warp(to: p)
        result(nil)
      case "click":
        guard let p = point() else { result(FlutterError(code: "args", message: "x,y required", details: nil)); return }
        let right = args["right"] as? Bool ?? false
        let count = args["count"] as? Int ?? 1
        Task {
          await ComputerControl.click(at: p, right: right, count: count)
          result(nil)
        }
      case "drag":
        guard
          let from = args["from"] as? [String: Double], let to = args["to"] as? [String: Double],
          let fx = from["x"], let fy = from["y"], let tx = to["x"], let ty = to["y"]
        else { result(FlutterError(code: "args", message: "from/to required", details: nil)); return }
        ComputerControl.dragBegin(at: CGPoint(x: fx, y: fy))
        ComputerControl.dragMove(to: CGPoint(x: tx, y: ty))
        ComputerControl.dragEnd(at: CGPoint(x: tx, y: ty))
        result(nil)
      case "scroll":
        guard let p = point() else { result(FlutterError(code: "args", message: "x,y required", details: nil)); return }
        let dx = args["dx"] as? Int ?? 0
        let dy = args["dy"] as? Int ?? 0
        Task {
          await ComputerControl.scroll(dx: dx, dy: dy, at: p)
          result(nil)
        }
      case "type":
        guard let text = args["text"] as? String else { result(FlutterError(code: "args", message: "text required", details: nil)); return }
        Task {
          await ComputerControl.type(text) { _ in }
          result(nil)
        }
      case "press":
        guard let combo = args["combo"] as? String else { result(FlutterError(code: "args", message: "combo required", details: nil)); return }
        do {
          result(try ComputerControl.press(combo))
        } catch {
          result(FlutterError(code: "press", message: error.localizedDescription, details: nil))
        }
      case "openApp":
        guard let name = args["name"] as? String else { result(FlutterError(code: "args", message: "name required", details: nil)); return }
        Task {
          result(await ComputerControl.openApp(name))
        }
      case "openURL":
        guard let url = args["url"] as? String else { result(FlutterError(code: "args", message: "url required", details: nil)); return }
        result(ComputerControl.openURL(url))
      case "snapshotRegion":
        Task {
          do {
            let args = call.arguments as? [String: Any]
            let rect = CGRect(
              x: args?["x"] as? Double ?? 0,
              y: args?["y"] as? Double ?? 0,
              width: args?["width"] as? Double ?? 0,
              height: args?["height"] as? Double ?? 0
            )
            let crop = try await ScreenReader.snapshotRegion(rect)
            result([
              "jpeg": FlutterStandardTypedData(bytes: crop.jpeg),
              // OCR text of this crop, checked by the privacy guard (#245).
              "targets": crop.text,
              // Set only after OCR completed for the exact captured image.
              // A successful empty string is valid evidence of a blank crop.
              "cropTextVerified": true,
              "width": Double(rect.width),
              "height": Double(rect.height),
              "app": lastSnapshot?.app ?? "",
            ])
          } catch {
            result(FlutterError(code: "snapshotRegion", message: error.localizedDescription, details: nil))
          }
        }
      case "snapshot":
        Task {
          do {
            let snap = try await ScreenReader.snapshot()
            lastSnapshot = snap
            result([
              "jpeg": FlutterStandardTypedData(bytes: snap.jpeg),
              "targets": snap.targetList,
              "width": Double(snap.size.width),
              "height": Double(snap.size.height),
              "app": snap.app as Any,
            ])
          } catch {
            result(FlutterError(code: "snapshot", message: error.localizedDescription, details: nil))
          }
        }
      case "resolveTarget":
        guard let id = args["id"] as? String else { result(FlutterError(code: "args", message: "id required", details: nil)); return }
        guard let snap = lastSnapshot else { result(FlutterError(code: "state", message: "Call snapshot first.", details: nil)); return }
        guard let target = snap.target(id) else { result(FlutterError(code: "notFound", message: "No target \(id). Use an id from the last snapshot.", details: nil)); return }
        result(["x": Double(target.rect.midX), "y": Double(target.rect.midY), "text": target.text])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
