import Cocoa
import FlutterMacOS

/// Flutter MethodChannel bridging the ported vision + control layer
/// (ScreenReader, ControlsReader, ComputerControl) to Dart.
final class NativeControlChannel {
  static let name = "local_bluey/control"

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
      case "askPermission":
        ComputerControl.askForPermission()
        result(nil)
      case "openAccessibilitySettings":
        ComputerControl.openAccessibilitySettings()
        result(nil)
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
      case "snapshot":
        Task {
          do {
            let snap = try await ScreenReader.snapshot()
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
