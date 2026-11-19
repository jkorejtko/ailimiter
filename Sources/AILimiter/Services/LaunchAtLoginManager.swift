import Foundation
import ServiceManagement

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()

    @Published public var isEnabled: Bool = false

    private init() {
        checkStatus()
    }

    public func checkStatus() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = (SMAppService.mainApp.status == .enabled)
        } catch {
            // Při vývoji bez instalace do /Applications může SMAppService vyžadovat registraci aplikace
            checkStatus()
        }
    }
}
