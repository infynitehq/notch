import XCTest
@testable import notch

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testAppEnvironmentDetectsRunningInTestEnvironment() {
        XCTAssertTrue(AppEnvironment.isRunningTests)
        XCTAssertTrue(AppEnvironment.isRunningUnitTests)
    }

    func testAppContainerInitializesInactiveServicesInTestEnvironment() {
        let container = AppContainer()
        XCTAssertTrue(container.bluetoothViewModel.deviceName == "Unknown")
        XCTAssertFalse(container.bluetoothViewModel.isConnected)
    }
}
