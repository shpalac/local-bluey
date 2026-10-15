import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {
  func testRunnerHostHasNativeExecutable() {
    let host = Bundle.main
    XCTAssertEqual(host.bundleURL.pathExtension, "app")
    guard let executable = host.executableURL else {
      XCTFail("macOS Runner host does not contain an executable")
      return
    }
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
  }
}
