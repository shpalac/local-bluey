import Cocoa
import FlutterMacOS

/// System-wide key listener for the hold-to-talk shortcut (#228).
///
/// Only reports raw key transitions to Dart; the long-press logic lives in
/// `HoldKeyMachine` (Dart) where it is unit tested. Off until Dart calls
/// `start`, and `start` refuses without the Input Monitoring permission.
final class HoldKeyChannel: NSObject, FlutterStreamHandler {
  static let methodName = "local_bluey/holdkey"
  static let eventName = "local_bluey/holdkey/events"
  private static let shared = HoldKeyChannel()

  private var sink: FlutterEventSink?
  private var globalMonitor: Any?
  private var localMonitor: Any?

  static func register(with controller: FlutterViewController) {
    let messenger = controller.engine.binaryMessenger
    FlutterEventChannel(name: eventName, binaryMessenger: messenger).setStreamHandler(shared)
    let method = FlutterMethodChannel(name: methodName, binaryMessenger: messenger)
    method.setMethodCallHandler { call, result in
      switch call.method {
      case "permission":
        // Preflight only: never prompts.
        result(CGPreflightListenEventAccess())
      case "requestPermission":
        result(CGRequestListenEventAccess())
      case "start":
        result(shared.start())
      case "stop":
        shared.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  /// Installs the monitors. Returns false (and installs nothing) without
  /// the Input Monitoring permission.
  private func start() -> Bool {
    guard CGPreflightListenEventAccess() else { return false }
    if globalMonitor == nil {
      globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
        self?.handle(event)
      }
    }
    if localMonitor == nil {
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
        self?.handle(event)
        return event
      }
    }
    return true
  }

  private func stop() {
    if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
    if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
    globalMonitor = nil
    localMonitor = nil
  }

  private static let modifierFlags: [UInt16: NSEvent.ModifierFlags] = [
    54: .command, 55: .command, 58: .option, 61: .option, 63: .function,
    56: .shift, 60: .shift, 59: .control, 62: .control, 57: .capsLock,
  ]

  private static func name(for keyCode: UInt16) -> String {
    switch keyCode {
    case 54: return "rightCommand"
    case 55: return "leftCommand"
    case 61: return "rightOption"
    case 63: return "fn"
    default: return "other"
    }
  }

  private func handle(_ event: NSEvent) {
    guard let sink = sink else { return }
    switch event.type {
    case .flagsChanged:
      let down = HoldKeyChannel.modifierFlags[event.keyCode].map { event.modifierFlags.contains($0) } ?? true
      sink(["type": down ? "down" : "up", "key": HoldKeyChannel.name(for: event.keyCode)])
    case .keyDown:
      // Esc cancels; any other key disqualifies the hold.
      sink(["type": event.keyCode == 53 ? "escape" : "down", "key": "other"])
    default:
      break
    }
  }
}
