import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var capture: CaptureController
    @State private var showingProvisioning = false
    @State private var showingBackgroundUpgrade = false

    var body: some View {
        VStack(spacing: 24) {
            if !capture.hasAPIKey {
                Button {
                    showingProvisioning = true
                } label: {
                    Label("No device key -- captured records won't upload. Tap to connect.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .padding(.top, 12)
            }

            if capture.canOfferBackgroundUpgrade {
                Button {
                    showingBackgroundUpgrade = true
                } label: {
                    Label("Capture pauses when the app closes. Tap to enable background capture.", systemImage: "moon.zzz")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityIdentifier("backgroundUpgradeBanner")
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(capture.isCapturing ? .green : .gray)
                    .frame(width: 16, height: 16)
                Text(capture.isCapturing ? "Capturing" : "Paused")
                    .font(.headline)
            }
            .padding(.top, 40)

            Text("\(capture.pendingCount) records queued for upload")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pendingCountLabel")

            Button(capture.isCapturing ? "Pause capture" : "Start capture") {
                capture.isCapturing ? capture.pause() : capture.start()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("captureToggleButton")

            Button("Sync now") {
                capture.syncNow()
            }
            .buttonStyle(.bordered)

            // Always reachable, not just via the "no key" banner above --
            // switching backends (e.g. local -> hosted dev) needs a new key
            // even when one is already stored, since it's scoped to the
            // device row on whichever backend issued it.
            Button("Device connection") {
                showingProvisioning = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.footnote)
            .accessibilityIdentifier("deviceConnectionButton")

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingProvisioning) {
            NavigationStack {
                ProvisioningView()
            }
        }
        .sheet(isPresented: $showingBackgroundUpgrade) {
            NavigationStack {
                BackgroundUpgradeView()
            }
        }
    }
}
