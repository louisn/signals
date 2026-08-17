import XCTest

/// Exercises the "Always" location upgrade flow end-to-end: onboarding ->
/// skip provisioning -> grant "When In Use" -> background-upgrade banner
/// appears -> explanation screen -> system "Always" prompt.
final class BackgroundUpgradeFlowUITests: XCTestCase {
    func testBackgroundUpgradeBannerAppearsAndPromptsAlways() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting-reset"]

        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            for label in ["Allow While Using App", "Allow Once", "Change to Always Allow", "Keep Only While Using App"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()

        let continueButton = app.buttons["onboardingContinueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        let skipProvisioningButton = app.buttons["skipProvisioningButton"]
        XCTAssertTrue(skipProvisioningButton.waitForExistence(timeout: 5))
        skipProvisioningButton.tap()

        let captureToggleButton = app.buttons["captureToggleButton"]
        XCTAssertTrue(captureToggleButton.waitForExistence(timeout: 5))
        captureToggleButton.tap()
        // The "When In Use" system alert is handled by the interruption
        // monitor, which only fires once the app receives another event.
        app.tap()

        let banner = app.buttons["backgroundUpgradeBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "banner should appear once When In Use is granted")
        banner.tap()

        let enableButton = app.buttons["enableBackgroundCaptureButton"]
        XCTAssertTrue(enableButton.waitForExistence(timeout: 5))
        enableButton.tap()
        // Triggers the system "Always" prompt, handled by the interruption monitor.
        app.tap()

        XCTAssertTrue(app.buttons["captureToggleButton"].waitForExistence(timeout: 5), "should return to the capture screen")
    }
}
