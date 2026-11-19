import SwiftUI

public struct DashboardView: View {
    @ObservedObject var monitor: LimitMonitor
    let onOpenSettings: () -> Void
    let onAddAccount: () -> Void
    let onEditAccount: (AccountCredential) -> Void

    public init(
        monitor: LimitMonitor,
        onOpenSettings: @escaping () -> Void,
        onAddAccount: @escaping () -> Void,
        onEditAccount: @escaping (AccountCredential) -> Void
    ) {
        self.monitor = monitor
        self.onOpenSettings = onOpenSettings
        self.onAddAccount = onAddAccount
        self.onEditAccount = onEditAccount
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Přehledový stav nahoře
                HStack {
                    Text("Aktivní účty: \(monitor.accounts.filter { $0.isEnabled }.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let lastRefresh = monitor.lastRefreshTime {
                        Text("Poslední kontrola: \(timeString(from: lastRefresh))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(.horizontal, 4)

                // Upozornění na Demo simulaci, pokud alespoň jeden účet nemá token
                if monitor.accounts.contains(where: { $0.isEnabled && $0.isDemo }) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Účty běží v demo simulaci")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)

                            Text(
                                "Zobrazují se statické hodnoty. Pro živé kvóty nastavte auto nebo přihlašovací token předplatného."
                            )
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }

                if monitor.accounts.isEmpty {
                    // Prázdný stav
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                            .padding(.top, 20)

                        Text("Zatím nemáte přidaný žádný AI účet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)

                        Button(action: onAddAccount) {
                            Label("Přidat první účet", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                } else if !monitor.accounts.contains(where: \.isEnabled) {
                    Text("Všechny účty jsou vypnuté.")
                    Button("Otevřít nastavení účtů", action: onOpenSettings)
                } else {
                    // Karty účtů
                    ForEach(monitor.accounts) { account in
                        if account.isEnabled {
                            ProviderCardView(
                                account: account,
                                status: monitor.statuses[account.id],
                                onRefresh: {
                                    Task {
                                        await monitor.refreshAccount(account)
                                    }
                                },
                                onEdit: {
                                    onEditAccount(account)
                                },
                                isRefreshing: monitor.generations[account.id] != nil
                            )
                        }
                    }

                    // Tlačítko přidat další účet dole
                    Button(action: onAddAccount) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13))
                            Text("Přidat další účet")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
