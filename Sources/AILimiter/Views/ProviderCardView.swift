import SwiftUI

public struct ProviderCardView: View {
    public let account: AccountCredential
    public let status: LimitStatus?
    public let onRefresh: () -> Void
    public var onEdit: (() -> Void)? = nil

    public init(
        account: AccountCredential,
        status: LimitStatus?,
        onRefresh: @escaping () -> Void,
        onEdit: (() -> Void)? = nil
    ) {
        self.account = account
        self.status = status
        self.onRefresh = onRefresh
        self.onEdit = onEdit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hlavička karty
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(account.provider.brandColor.opacity(0.18))
                        .frame(width: 34, height: 34)

                    Image(systemName: account.provider.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(account.provider.brandColor)
                }

                let mainTitle = account.displayTitle
                let subTitle = status?.planName ?? account.provider.defaultPlan
                let isActuallyDemo = status?.isDemo ?? account.isDemo

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mainTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if isActuallyDemo {
                            Text("DEMO")
                                .font(.system(size: 8, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.18))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }

                        if let credits = status?.resetCreditsCount, credits > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "ticket.fill")
                                    .font(.system(size: 8))
                                Text("\(credits) kredit\(credits == 1 ? "" : (credits < 5 ? "y" : "ů"))")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        }
                    }

                    Text(subTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Stavový odznak
                if let health = status?.healthState {
                    StatusBadge(health: status?.refreshError == nil ? health : .unavailable, isDemo: account.isDemo || status?.isDemo == true)
                }
            }

            // Plovoucí okna limitů (T3 Code multi-window layout)
            if let status = status, status.hasUsageData {
                if !status.windows.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(status.windows) { window in
                            WindowRowView(window: window)
                        }
                    }
                } else {
                    // Fallback pro starší API bez rozpadu na okna
                    SingleBarView(
                        percentage: status.usagePercentage,
                        health: status.healthState,
                        resetText: status.resetCountdownString
                    )
                }
            } else if let status = status {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text(status.statusDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            }

            if let status, let error = status.refreshError {
                Text("Poslední známá data (\(status.lastChecked.formatted(date: .omitted, time: .shortened))). \(error)")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Spodní řádek: popis stavu a akce
            let isActuallyDemo = status?.isDemo ?? account.isDemo
            HStack(spacing: 6) {
                if status?.hasUsageData != false {
                    Text(status?.statusDescription ?? "Načítám stav...")
                        .font(.system(size: 11))
                        .foregroundColor(isActuallyDemo ? .orange.opacity(0.9) : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                if (isActuallyDemo || status?.hasUsageData == false), let onEdit = onEdit {
                    Button(action: onEdit) {
                        Text(status?.healthState == .error ? "Nastavit token" : "Zadat token")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(status?.healthState == .error ? .red : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background((status?.healthState == .error ? Color.red : Color.orange).opacity(0.12))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Zadat skutečný token nebo použít auto-detekci")
                }

                if let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Upravit účet")
                }

                // Otevřít web služby
                Button(action: {
                    NSWorkspace.shared.open(account.provider.webUrl)
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Otevřít \(account.provider.displayName) v prohlížeči")

                // Ruční obnovení tohoto účtu
                Button(action: onRefresh) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Obnovit tento účet")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(account.isDemo ? Color.orange.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Pomocné komponenty pro okna a progress bary

struct WindowRowView: View {
    let window: UsageWindow

    var barColor: Color {
        if window.usedPercent >= 100.0 {
            return Color(red: 0.91, green: 0.30, blue: 0.24)
        } else if window.usedPercent >= 80.0 {
            return Color(red: 0.96, green: 0.65, blue: 0.14)
        } else {
            return Color(red: 0.18, green: 0.80, blue: 0.44)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))

                if let pace = window.pace {
                    HStack(spacing: 2) {
                        Image(systemName: pace.iconName)
                            .font(.system(size: 9))
                        Text(pace.label)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(pace.color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(pace.color.opacity(0.12))
                    .cornerRadius(3)
                }

                Spacer()

                Text("\(Int(window.usedPercent))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(window.usedPercent >= 100.0 ? .red : (window.usedPercent >= 80.0 ? .orange : .secondary))

                if let countdown = window.resetCountdownString {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(countdown)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(window.usedPercent >= 100.0 ? .red : .secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3.5)
                        .fill(barColor)
                        .frame(
                            width: max(0, min(geometry.size.width * CGFloat(window.usedPercent / 100.0), geometry.size.width)),
                            height: 6
                        )
                        .animation(.spring(response: 0.4), value: window.usedPercent)
                }
            }
            .frame(height: 6)
        }
    }
}

struct SingleBarView: View {
    let percentage: Double
    let health: LimitHealthState
    let resetText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 7)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(health.color)
                        .frame(
                            width: max(0, min(geometry.size.width * CGFloat(percentage / 100.0), geometry.size.width)),
                            height: 7
                        )
                        .animation(.spring(response: 0.4), value: percentage)
                }
            }
            .frame(height: 7)

            HStack {
                if percentage > 0.0 {
                    Text("\(Int(percentage))% vyčerpáno")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    Text("Aktivní v normě")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let resetText = resetText {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(resetText)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(health == .exhausted ? .red : .secondary)
                }
            }
        }
    }
}

struct StatusBadge: View {
    let health: LimitHealthState
    var isDemo: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isDemo ? Color.orange : health.color)
                .frame(width: 6, height: 6)

            Text(isDemo ? "DEMO" : health.badgeTitle)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isDemo ? Color.orange : health.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isDemo ? Color.orange : health.color).opacity(0.12))
        .cornerRadius(6)
    }
}
