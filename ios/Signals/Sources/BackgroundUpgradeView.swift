import SwiftUI

/// Explains the "Always" location upgrade before the system prompt appears,
/// per the plan's requirement that this be a distinct, explicitly-justified
/// ask rather than bundled into the initial "When In Use" request. Shown
/// only while `CaptureController.canOfferBackgroundUpgrade` is true --
/// i.e. "When In Use" is already granted and the user hasn't skipped this
/// screen before.
struct BackgroundUpgradeView: View {
    @EnvironmentObject private var capture: CaptureController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("Signals can keep capturing location and nearby Bluetooth signals when the app isn't open, so records stay continuous instead of resuming only when you return to the app.")
                    .foregroundStyle(.secondary)
                Text("This requires \"Always\" location access. iOS will ask you to confirm.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Enable background capture") {
                    capture.requestBackgroundLocationUpgrade()
                    dismiss()
                }
                .accessibilityIdentifier("enableBackgroundCaptureButton")
            }

            Section {
                Button("Not now") {
                    capture.skipBackgroundUpgrade()
                    dismiss()
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("skipBackgroundUpgradeButton")
            }
        }
        .navigationTitle("Background capture")
    }
}
