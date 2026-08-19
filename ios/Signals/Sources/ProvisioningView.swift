import SwiftUI
import SignalKit

/// Shown after onboarding when the device has no stored API key yet.
/// Two paths, deliberately asymmetric in what ships:
///
/// - Paste a pre-provisioned key: always available, safe to ship, for the
///   normal flow where ops/admin provisions a device out-of-band and hands
///   the resulting key to whoever sets the device up.
/// - Provision via admin key: `#if DEBUG` only. Calls the admin-protected
///   endpoint directly from the device, which is a dev/ops convenience for
///   fast local iteration -- the admin key must never ship in a release
///   build, so this path is compiled out entirely for release builds
///   rather than merely hidden.
struct ProvisioningView: View {
    @EnvironmentObject private var capture: CaptureController
    @Environment(\.dismiss) private var dismiss
    @State private var pastedKey = ""
    #if DEBUG
    @State private var adminKey = ""
    @State private var deviceLabel = ""
    @State private var isProvisioning = false
    @State private var errorMessage: String?
    #endif

    var body: some View {
        Form {
            Section {
                Text("This device needs an API key before it can upload captured signals. Capture still works and queues locally without one.")
                    .foregroundStyle(.secondary)
            }

            Section("Scan to connect") {
                Text("Open your Camera and scan the QR from the backend's provisioning page. The app connects automatically -- nothing to type.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            Section("I have a device API key") {
                SecureField("API key", text: $pastedKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pastedAPIKeyField")
                Button("Save key") {
                    capture.saveAPIKey(pastedKey)
                    dismiss()
                }
                .disabled(pastedKey.isEmpty)
                .accessibilityIdentifier("saveKeyButton")
            }

            #if DEBUG
            Section("Provision via admin key (dev only)") {
                SecureField("Admin key", text: $adminKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("adminKeyField")
                TextField("Device label (optional)", text: $deviceLabel)
                    .accessibilityIdentifier("deviceLabelField")
                Button("Provision this device") {
                    provisionViaAdminKey()
                }
                .disabled(adminKey.isEmpty || isProvisioning)
                .accessibilityIdentifier("provisionButton")
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .accessibilityIdentifier("provisioningErrorText")
                }
            }
            #endif

            Section {
                Button("Skip for now") {
                    capture.skipProvisioning()
                    dismiss()
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("skipProvisioningButton")
            }
        }
        .navigationTitle("Connect device")
    }

    #if DEBUG
    private func provisionViaAdminKey() {
        isProvisioning = true
        errorMessage = nil
        Task {
            do {
                try await capture.provisionViaAdminKey(adminKey: adminKey, label: deviceLabel)
                dismiss()
            } catch {
                errorMessage = "Provisioning failed: \(error)"
            }
            isProvisioning = false
        }
    }
    #endif
}
