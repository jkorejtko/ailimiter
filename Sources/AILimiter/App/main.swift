import AppKit

@main
struct AILimiterApp {
    @MainActor
    static func main() {
        // Inicializace bezpečnostního záchranného systému pádů
        CrashHandler.shared.install()

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
