import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {
  func testAppDelegateTerminatesWhenLastWindowCloses() {
    let delegate = AppDelegate()
    XCTAssertTrue(
      delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
    )
  }
}
