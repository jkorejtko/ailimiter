import SwiftUI

public struct ProviderCardView: View {
    public let account: AccountCredential
    public let status: LimitStatus?
    public let onRefresh: () -> Void

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
                    Text(account.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

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
                        Text("\(Int(status.usagePercentage))% využito")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

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
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

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
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
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
