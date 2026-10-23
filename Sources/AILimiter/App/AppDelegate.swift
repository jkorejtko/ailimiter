import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Skrytí z Docku (Accessory UI element pro menu bar)
        NSApp.setActivationPolicy(.accessory)

        // Nastavení systémového Edit menu pro fungování Cmd+C, Cmd+V, Cmd+A, Cmd+X
        setupEditMenu()

        // Inicializace ikony v menu baru
        menuBarController = MenuBarController()

        // Žádost o povolení notifikací
        NotificationService.shared.requestAuthorization()
    }

    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Zpět", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Znovu", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Vyjmout", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopírovat", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Vložit", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Vybrat vše", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    public func applicationWillTerminate(_ notification: Notification) {
    }
}
