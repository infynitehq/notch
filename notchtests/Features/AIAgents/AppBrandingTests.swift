import AppKit
import XCTest
@testable import notch

@MainActor
final class AppBrandingTests: XCTestCase {
    func testAppUsesNotchNameAndFreshIdentity() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Notch")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "Notch")
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleExecutable"] as? String, "notch")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "in.infynite.notch")
    }

    func testCompiledAppIconAndAdaptiveBrandImageAreBundled() {
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleIconName"] as? String, "notch")
        XCTAssertNotNil(Bundle.main.url(forResource: "notch", withExtension: "icns"))
        XCTAssertNotNil(NSImage(named: "notchbrand"))
    }

    func testAgentSetupKitIsComplete() {
        for name in AgentIntegrationManager.kitFiles {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: nil), "Missing adapter resource: \(name)")
        }
    }

    func testUpdatesUseOnlyNotchTrustAndAreOptIn() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                       "https://github.com/infynitehq/notch/releases/latest/download/appcast.xml")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                       "ga0m4nh4WzDBjNPySlqj/OTe9kqnL0sHLOK+hk3NLm8=")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool, false)
    }
}
