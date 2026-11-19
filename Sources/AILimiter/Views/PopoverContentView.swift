import SwiftUI

public enum PopoverTab {
    case dashboard
    case settings
}

public struct PopoverContentView: View {
    @StateObject private var monitor = LimitMonitor.shared
    @State private var currentTab: PopoverTab = .dashboard
    @State private var showingAddAccountSheet: Bool = false
    @State private var editingAccount: AccountCredential? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Hlavní horní lišta (Header)
            HStack(spacing: 8) {
                // Ikona a název
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 24, height: 24)

                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.accentColor)
                }

                Text("AILimiter")
                    .font(.system(size: 13, weight: .bold))

                // Celkový indikátor stavu
                Circle()
                    .fill(monitor.globalState.color)
                    .frame(width: 7, height: 7)

                Spacer()

                // Tlačítko Obnovit vše
                Button(action: {
                    Task {
                        await monitor.refreshAll()
                    }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(monitor.isRefreshing ? 360 : 0))
                        .animation(
                            monitor.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default,
                            value: monitor.isRefreshing
                        )
                }
                .buttonStyle(.plain)
                .disabled(monitor.isRefreshing)
                .help("Obnovit všechny limity nyní")

                // Tlačítko Nastavení
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentTab = (currentTab == .dashboard) ? .settings : .dashboard
                    }
                }) {
                    Image(systemName: currentTab == .dashboard ? "gearshape" : "chart.bar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(currentTab == .dashboard ? "Nastavení účtů" : "Zpět na přehled")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if let error = monitor.storageError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.system(size: 11)).foregroundColor(.red)
                    Button("Zkusit úložiště znovu") { monitor.retryStorage() }
                }
                .padding(10)
            }

            // Obsah dle aktivní záložky
            Group {
                switch currentTab {
                case .dashboard:
                    DashboardView(
                        monitor: monitor,
                        onOpenSettings: { currentTab = .settings },
                        onAddAccount: {
                            editingAccount = nil
                            showingAddAccountSheet = true
                        },
                        onEditAccount: { acc in
                            editingAccount = acc
                            showingAddAccountSheet = true
                        }
                    )
                case .settings:
                    SettingsView(
                        monitor: monitor,
                        onBack: { currentTab = .dashboard },
                        onEditAccount: { acc in
                            editingAccount = acc
                            showingAddAccountSheet = true
                        },
                        onAddAccount: {
                            editingAccount = nil
                            showingAddAccountSheet = true
                        }
                    )
                }
            }
        }
        .frame(width: 360)
        .sheet(isPresented: $showingAddAccountSheet) {
            AddAccountSheet(
                monitor: monitor,
                accountToEdit: editingAccount,
                onDismiss: {
                    showingAddAccountSheet = false
                    editingAccount = nil
                }
            )
        }
    }
}
