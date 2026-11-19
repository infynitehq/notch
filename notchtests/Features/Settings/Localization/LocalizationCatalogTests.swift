import XCTest
@testable import notch

final class LocalizationCatalogTests: XCTestCase {
    func testEnglishStringsResolveRegardlessOfRequestedLocale() {
        XCTAssertEqual(L10n.app("menuBar.settings"), "Settings")
        XCTAssertEqual(Locale(identifier: "ru").dn("menuBar.settings"), "Settings")
        XCTAssertEqual(L10n.notch("common.cancel"), "Cancel")
    }

    func testMissingStringsHaveExplicitFallbacks() {
        XCTAssertEqual(L10n.app("missing.key", fallback: "Readable fallback"), "Readable fallback")
    }

    func testVersionFormatResolves() {
        XCTAssertEqual(L10n.locale.dnFormat("menuBar.version", fallback: nil, "1.0"), "Version: 1.0")
    }

    func testFreshIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "in.infynite.notch")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "notch")
    }
}
