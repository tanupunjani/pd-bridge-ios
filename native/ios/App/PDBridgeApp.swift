import SwiftUI
import UIKit

final class PDBridgeAppDelegate: NSObject, UIApplicationDelegate {
    // Evaluate before DiaryModel opens the vault. Existing diaries and saved
    // preferences predate the welcome marker and must open directly to Home.
    let showWelcomeAtLaunch = WelcomeGate.shouldShowAtLaunch()
    let diary = DiaryModel()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
#if PD_BRIDGE_SYNTHETIC_BUILD
        diary.startWatch()
#endif
        return true
    }
}

@main
struct PDBridgeApp: App {
    @UIApplicationDelegateAdaptor(PDBridgeAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootExperience(showWelcome: delegate.showWelcomeAtLaunch)
                .environmentObject(delegate.diary)
        }
    }
}

private enum WelcomeGate {
    static let key = "pdbridge.welcomeCompleted.v1"

    static func shouldShowAtLaunch(defaults: UserDefaults = .standard,
                                   applicationSupport: URL? = FileManager.default.urls(
                                    for: .applicationSupportDirectory, in: .userDomainMask).first) -> Bool {
        if defaults.object(forKey: key) != nil { return !defaults.bool(forKey: key) }
        let hasEarlierPreference = ["pdbridge.language", "pdbridge.comfortMode",
            "pdbridge.medicationReminder.enabled", "pdbridge.medicationReminder.hour"].contains {
                defaults.object(forKey: $0) != nil
            }
        let hasEarlierDiary = applicationSupport.map {
            FileManager.default.fileExists(atPath: $0
                .appendingPathComponent("PD Bridge Observations", isDirectory: true)
                .appendingPathComponent("observations-v1.bin").path)
        } ?? false
        if hasEarlierPreference || hasEarlierDiary {
            defaults.set(true, forKey: key)
            return false
        }
        return true
    }
}

private struct RootExperience: View {
    @State private var showWelcome: Bool

    init(showWelcome: Bool) { _showWelcome = State(initialValue: showWelcome) }

    var body: some View {
        if showWelcome {
            WelcomeView {
                UserDefaults.standard.set(true, forKey: WelcomeGate.key)
                showWelcome = false
            }
        } else {
            MainTabs()
        }
    }
}
