import XCTest

/// Exercises the in-app provisioning flow end-to-end against a real
/// backend: onboarding -> admin-key provisioning -> main capture screen.
/// Requires `backend/signals-backend` running locally at
/// `http://localhost:8080` with `ADMIN_KEY=dev-admin-key` (matching this
/// test's input) and reachable from the simulator.
final class ProvisioningFlowUITests: XCTestCase {
    func testProvisionViaAdminKeyReachesCaptureScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting-reset"]
        app.launch()

        let continueButton = app.buttons["onboardingContinueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        let adminKeyField = app.secureTextFields["adminKeyField"]
        XCTAssertTrue(adminKeyField.waitForExistence(timeout: 5), "provisioning screen should appear once no key is stored")
        adminKeyField.tap()
        adminKeyField.typeText("dev-admin-key")

        let labelField = app.textFields["deviceLabelField"]
        labelField.tap()
        labelField.typeText("uitest-device")

        app.buttons["provisionButton"].tap()

        let pendingCountLabel = app.staticTexts["pendingCountLabel"]
        XCTAssertTrue(pendingCountLabel.waitForExistence(timeout: 10), "should land on the capture screen after successful provisioning")

        let errorText = app.staticTexts["provisioningErrorText"]
        XCTAssertFalse(errorText.exists, "provisioning should have succeeded, not shown an error")
    }
}
