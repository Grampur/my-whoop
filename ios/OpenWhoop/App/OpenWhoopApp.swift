import SwiftUI
import BackgroundTasks

@main
struct OpenWhoopApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
        .backgroundTask(.appRefresh("com.openwhoop.refresh")) {
            await handleBackgroundRefresh()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
            }
            if phase == .background {
                scheduleBackgroundRefresh()
            }
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.openwhoop.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min minimum
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh() async {
        let repo = MetricsRepository(deviceId: AppConfig.deviceId)
        await repo.refresh()
    }
}

extension Notification.Name {
    static let appDidBecomeActive = Notification.Name("appDidBecomeActive")
}

/// Thin root wrapper that creates a MetricsRepository and LiveViewModel synchronously (no
/// async window) and immediately injects them as environment objects so RootTabView + its
/// tabs always receive non-nil @EnvironmentObjects from the very first render frame.
///
/// LiveViewModel owns the single BLEManager / CBCentralManager. Creating it here (at app
/// launch) means state-restoration fires in the same process lifetime as the manager, and
/// both the Device tab and the Alarm sheet share the same BLE connection.
///
/// The MetricsRepository opens its on-disk store lazily (on the first load/refresh call),
/// so there is no need to wait for an async factory before showing the UI.
private struct AppRoot: View {
    @StateObject private var metrics = MetricsRepository(deviceId: AppConfig.deviceId)
    @StateObject private var live    = LiveViewModel(deviceId: AppConfig.deviceId)
    
    var body: some View {
        RootTabView()
            .environmentObject(metrics)
            .environmentObject(live)
            .onAppear {
                RecoveryNotifier.requestAuthorization()
                SyncNudge.requestAuthorization()
            }
    }
}
