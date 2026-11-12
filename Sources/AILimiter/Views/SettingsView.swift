import SwiftUI

public struct SettingsView: View {
    @ObservedObject var monitor: LimitMonitor
    let onBack: () -> Void
    let onEditAccount: (AccountCredential) -> Void
    let onAddAccount: () -> Void

    @State private var accountToDelete: AccountCredential? = nil
    @State private var showingDeleteConfirmation: Bool = false

    public var body: some View {
        VStack(spacing: 12) {
            // Hlavička nastavení
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Zpět")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Nastavení")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button(action: onAddAccount) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Sekce: Správa účtů
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SPRAVOVANÉ AI ÚČTY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        if monitor.accounts.isEmpty {
                            Text("Žádné účty. Klikněte na + pro přidání.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(monitor.accounts) { account in
                                    HStack(spacing: 8) {
                                        Image(systemName: account.provider.iconName)
                                            .foregroundColor(account.provider.brandColor)
                                            .frame(width: 18)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(account.title)
                                                .font(.system(size: 12, weight: .medium))
                                            Text(account.provider.displayName)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Toggle("", isOn: Binding(
                                            get: { account.isEnabled },
                                            set: { _ in monitor.toggleAccount(id: account.id) }
                                        ))
                                        .toggleStyle(.switch)
                                        .controlSize(.mini)

                                        Button(action: { onEditAccount(account) }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: {
                                            accountToDelete = account
                                            showingDeleteConfirmation = true
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundColor(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Odebrat účet")
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(0.03))
                                    .cornerRadius(8)
                                }
                            }
                        }

                        Button(action: {
                            monitor.resetToAutoDetect()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                Text("Obnovit auto-detekci (Codex & Antigravity)")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .help("Vymaže staré neplatné tokeny a načte živé profily ze systému")
                    }

                    Divider()

                    // Sekce: Interval obnovování
                    VStack(alignment: .leading, spacing: 6) {
                        Text("INTERVAL KONTROLY LIMITŮ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Picker("", selection: Binding(
                            get: { monitor.refreshIntervalMinutes },
                            set: { monitor.setRefreshInterval($0) }
                        )) {
                            Text("Každé 2 minuty").tag(2)
                            Text("Každých 5 minut").tag(5)
                            Text("Každých 10 minut").tag(10)
                            Text("Každých 30 minut").tag(30)
                        }
                        .pickerStyle(.menu)
                    }

                    Divider()

                    // Sekce: Spuštění při startu systému
                    VStack(alignment: .leading, spacing: 6) {
                        Text("START SE SYSTÉMEM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Toggle(isOn: Binding(
                            get: { LaunchAtLoginManager.shared.isEnabled },
                            set: { LaunchAtLoginManager.shared.setLaunchAtLogin($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Spustit automaticky po zapnutí Macu")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Aplikace naskočí do menu baru hned po restartu")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    Divider()

                    // Otestovat notifikaci
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SYSTÉMOVÉ NOTIFIKACE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Button(action: {
                            NotificationService.shared.sendWarningNotification(
                                provider: .claude,
                                usagePercent: 85.0
                            )
                        }) {
                            Label("Vyzkoušet zkušební notifikaci", systemImage: "bell.badge")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()

                    // Ukončení aplikace
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("AILimiter v1.0")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Běží tiše v macOS menu baru")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            NSApplication.shared.terminate(nil)
                        }) {
                            Text("Ukončit aplikaci")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
            }
        }
        .alert(
            "Odebrat spárovaný účet?",
            isPresented: $showingDeleteConfirmation,
            presenting: accountToDelete
        ) { account in
            Button("Odebrat", role: .destructive) {
                monitor.deleteAccount(id: account.id)
                accountToDelete = nil
            }
            Button("Zrušit", role: .cancel) {
                accountToDelete = nil
            }
        } message: { account in
            Text("Opravdu chcete odebrat účet „\(account.title)“ (\(account.provider.displayName))? Uložené přihlašovací údaje a klíče budou smazány.")
        }
    }
}
