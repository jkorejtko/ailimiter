import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Skrytí z Docku (Accessory UI element pro menu bar)
        NSApp.setActivationPolicy(.accessory)

        // Inicializace ikony v menu baru
        menuBarController = MenuBarController()

        // Žádost o povolení notifikací
        NotificationService.shared.requestAuthorization()
    }

    public func applicationWillTerminate(_ notification: Notification) {
    }
}
