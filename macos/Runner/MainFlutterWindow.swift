import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    NativeControlChannel.register(with: flutterViewController)
    AudioDecoderChannel.register(with: flutterViewController)
    HoldKeyChannel.register(with: flutterViewController)
    let fileIndexChannel = FlutterMethodChannel(
      name: "local_bluey/file_index",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    fileIndexChannel.setMethodCallHandler { call, result in
      guard call.method == "chooseDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let panel = NSOpenPanel()
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.allowsMultipleSelection = false
      panel.prompt = "Select for indexing"
      panel.begin { response in
        result(response == .OK ? panel.url?.path : nil)
      }
    }

    super.awakeFromNib()
  }
}
