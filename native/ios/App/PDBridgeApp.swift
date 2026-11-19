import SwiftUI
import UIKit

final class PDBridgeAppDelegate: NSObject, UIApplicationDelegate {
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
            MainTabs()
                .environmentObject(delegate.diary)
        }
    }
}
