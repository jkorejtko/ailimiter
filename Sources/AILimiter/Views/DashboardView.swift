import SwiftUI

public struct DashboardView: View {
    @ObservedObject var monitor: LimitMonitor
    let onOpenSettings: () -> Void
    let onAddAccount: () -> Void

    public var body: some View {
        VStack(spacing: 12) {
            // Přehledový stav nahoře
            HStack {
                Text("Aktivní účty: \(monitor.accounts.filter { $0.isEnabled }.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if let lastRefresh = monitor.lastRefreshTime {
                    Text("Naposledy: \(timeString(from: lastRefresh))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .padding(.horizontal, 4)

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
                            }
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

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
