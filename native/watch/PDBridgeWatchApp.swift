import SwiftUI
import WatchKit

final class PDBridgeWatchDelegate: NSObject, WKApplicationDelegate {
    let transfer = WatchTransfer()

    func applicationDidFinishLaunching() { transfer.start() }
}

@main
struct PDBridgeWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: PDBridgeWatchDelegate

    var body: some Scene {
        WindowGroup {
            WatchScreen(transfer: delegate.transfer)
        }
    }
}

private struct WatchScreen: View {
    @ObservedObject var transfer: WatchTransfer

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("PD Bridge")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Fictional test only. No fall detection or health access.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Send Fictional Test Event") {
                    transfer.sendFictionalEvent()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.086, green: 0.373, blue: 0.333))
                .frame(maxWidth: .infinity, minHeight: 56)
                .accessibilityHint("Queues a fixed fictional event. The watch keeps it until the iPhone confirms storage.")
                Text(transfer.status)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Fictional Watch event delivery status")
                    .accessibilityValue(transfer.status)
                    .accessibilityAddTraits(.updatesFrequently)
                if transfer.pendingCount > 0 {
                    Label("\(transfer.pendingCount) fictional event(s) still queued on this watch", systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Pending fictional Watch events: \(transfer.pendingCount)")
                    Button("Retry pending") { transfer.retryPending() }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .accessibilityLabel("Retry pending fictional event delivery")
                        .accessibilityHint("Sends queued fictional events again without changing their event identifiers")
                }
            }
            .padding(10)
        }
    }
}
