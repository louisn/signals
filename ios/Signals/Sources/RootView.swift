import SwiftUI

private let hasAcknowledgedConsentKey = "hasAcknowledgedConsent"

struct RootView: View {
    @AppStorage(hasAcknowledgedConsentKey) private var hasAcknowledgedConsent = false
    @EnvironmentObject private var capture: CaptureController

    var body: some View {
        if !hasAcknowledgedConsent {
            OnboardingView {
                hasAcknowledgedConsent = true
            }
        } else if !capture.hasAPIKey && !capture.hasSkippedProvisioning {
            NavigationStack {
                ProvisioningView()
            }
        } else {
            ContentView()
        }
    }
}
