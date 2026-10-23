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

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if account.isDemo {
                            Text("DEMO")
                                .font(.system(size: 8, weight: .heavy))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.18))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }

                    Text(status?.planName ?? account.provider.defaultPlan)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Stavový odznak
                if let health = status?.healthState {
                    StatusBadge(health: health)
                }
            }

            // Progress bar
            if let status = status, status.healthState != .error {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 7)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(status.healthState.color)
                                .frame(
                                    width: max(0, min(geometry.size.width * CGFloat(status.usagePercentage / 100.0), geometry.size.width)),
                                    height: 7
                                )
                                .animation(.spring(response: 0.4), value: status.usagePercentage)
                        }
                    }
                    .frame(height: 7)

                    // Textové info pod progress barem
                    HStack {
                        if status.usagePercentage > 0.0 {
                            Text("\(Int(status.usagePercentage))% vyčerpáno")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            Text("V normě (0% vyčerpáno)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if let resetText = status.resetCountdownString {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text(resetText)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(status.healthState == .exhausted ? .red : .secondary)
                        }
                    }
                }
            }

            // Spodní řádek: popis stavu a akce
            HStack {
                Text(status?.statusDescription ?? "Načítám stav...")
                    .font(.system(size: 11))
                    .foregroundColor(account.isDemo ? .orange.opacity(0.9) : .secondary)
                    .lineLimit(1)

                Spacer()

                if account.isDemo, let onEdit = onEdit {
                    Button(action: onEdit) {
                        Text("Zadat token")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Zadat skutečný token pro živá data")
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

struct StatusBadge: View {
    let health: LimitHealthState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(health.color)
                .frame(width: 6, height: 6)

            Text(health.badgeTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(health.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(health.color.opacity(0.12))
        .cornerRadius(6)
    }
}
