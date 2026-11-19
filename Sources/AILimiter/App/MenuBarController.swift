import AppKit
import SwiftUI
import Combine

@MainActor
public final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    private var monitor = LimitMonitor.shared
    private var isEditingAccount = false

    override public init() {
        super.init()
        setupStatusItem()
        setupPopover()
        observeMonitor()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            updateButtonAppearance(state: monitor.globalState)
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 460)
        popover.behavior = .transient
        popover.animates = true
        var content = PopoverContentView()
        content.onEditorVisibilityChanged = { [weak self] editing in
            self?.isEditingAccount = editing
            self?.popover.behavior = editing ? .applicationDefined : .transient
        }
        popover.contentViewController = NSHostingController(rootView: content)
    }

    private func observeMonitor() {
        monitor.$statuses
            .combineLatest(monitor.$accounts, monitor.$storageError)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateButtonAppearance(state: self.monitor.globalState)
            }
            .store(in: &cancellables)
    }

    private func updateButtonAppearance(state: LimitHealthState) {
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let symbolName: String
        switch state {
        case .exhausted:
            symbolName = "exclamationmark.triangle.fill"
        case .warning:
            symbolName = "sparkle"
        case .error, .unavailable:
            symbolName = "questionmark.circle"
        case .normal:
            symbolName = "sparkles"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AILimiter")?.withSymbolConfiguration(config) {
            image.isTemplate = (state == .normal)
            button.image = image
        }

        button.toolTip = "AILimiter – Stav AI limitů (\(state.badgeTitle))"
        button.setAccessibilityLabel("AILimiter – \(state.badgeTitle)")
    }

    @objc public func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            guard !isEditingAccount else { return }
            popover.performClose(nil)
        } else {
            if let controller = popover.contentViewController {
                let fitting = controller.view.fittingSize
                if fitting.height > 0 {
                    popover.contentSize = fitting
                }
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
