import AppKit
import XCTest
@testable import notch

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testClosingManagementWindowDoesNotTerminateMenuBarApp() {
        let delegate = AppDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
