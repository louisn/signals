import SwiftUI

/// First-launch consent screen. Distinct from (and shown before) the OS
/// location/Bluetooth permission dialogs -- this is org-deployed-instrument
/// consent, stating plainly what's collected before capture ever starts.
struct OnboardingView: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Before you start")
                .font(.title2.bold())

            Text("This app records the following signals, tagged with your location and timestamp, and uploads them to the project's backend:")

            VStack(alignment: .leading, spacing: 8) {
                Label("GPS location", systemImage: "location.fill")
                Label("Nearby Bluetooth devices", systemImage: "dot.radiowaves.left.and.right")
                Label("Current network name and carrier", systemImage: "wifi")
            }
            .font(.callout)

            Text("Capture only runs while you've turned it on in the app. You can pause it at any time from the main screen.")
                .foregroundStyle(.secondary)

            Spacer()

            Button("I understand, continue") {
                onAcknowledge()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("onboardingContinueButton")
        }
        .padding()
    }
}
