import SwiftUI
import UniformTypeIdentifiers

public struct AddAccountSheet: View {
    @ObservedObject var monitor: LimitMonitor
    public var accountToEdit: AccountCredential?
    public var onDismiss: () -> Void

    @State private var selectedProvider: AIProvider = .chatgpt
    @State private var title: String = ""
    @State private var token: String = ""
    @State private var isHelpExpanded: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: String? = nil
    @State private var isTokenVisible: Bool = false
    @State private var useLocalProfile: Bool = true
    @State private var profilePath: String?

    private var effectiveToken: String {
        useLocalProfile && selectedProvider.supportsLocalProfiles
            ? "auto" : token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedProfilePath: String? {
        useLocalProfile && selectedProvider.supportsLocalProfiles ? profilePath : nil
    }

    public init(monitor: LimitMonitor, accountToEdit: AccountCredential? = nil, onDismiss: @escaping () -> Void) {
        self.monitor = monitor
        self.accountToEdit = accountToEdit
        self.onDismiss = onDismiss
        _selectedProvider = State(initialValue: accountToEdit?.provider ?? .chatgpt)
        _title = State(initialValue: accountToEdit?.displayTitle ?? "")
        _token = State(initialValue: accountToEdit?.token ?? "")
        _useLocalProfile = State(
            initialValue: accountToEdit.map {
                $0.token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto"
            } ?? true)
        _profilePath = State(initialValue: accountToEdit?.profilePath)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Hlavička
            HStack {
                Text(accountToEdit == nil ? "Přidat AI Účet" : "Upravit Účet")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Výběr AI Providera
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Služba")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(AIProvider.allCases) { provider in
                                ProviderSelectButton(
                                    provider: provider,
                                    isSelected: selectedProvider == provider,
                                    onSelect: {
                                        guard selectedProvider != provider else { return }
                                        selectedProvider = provider
                                        useLocalProfile = provider.supportsLocalProfiles
                                        profilePath = nil
                                        token = ""
                                        testResult = nil
                                        if title.isEmpty || AIProvider.allCases.map({ $0.displayName }).contains(title)
                                        {
                                            title = provider.displayName
                                        }
                                    }
                                )
                            }
                        }
                    }

                    // Název účtu
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Vlastní název")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        TextField("Např. Osobní Plus, Pracovní...", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    if selectedProvider.supportsLocalProfiles {
                        Picker("Přihlášení", selection: $useLocalProfile) {
                            Text("Lokální profil").tag(true)
                            Text("Vložit token").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: useLocalProfile) { local in
                            if !local && token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto" {
                                token = ""
                            }
                            testResult = nil
                        }
                    }

                    if useLocalProfile && selectedProvider.supportsLocalProfiles {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profilePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Výchozí profil")
                                .font(.system(size: 12, weight: .semibold))
                                .help(profilePath ?? selectedProvider.defaultProfileDescription)
                            Text(
                                profilePath == nil
                                    ? selectedProvider.defaultProfileDescription
                                    : "Použije se pouze vybraný soubor; jiný účet se automaticky nehledá."
                            )
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Vybrat soubor…", action: chooseProfile)
                                if profilePath != nil {
                                    Button("Použít výchozí") {
                                        profilePath = nil
                                        testResult = nil
                                    }
                                }
                            }
                            Text(selectedProvider.tokenHelp)
                                .font(.system(size: 11)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        // Token / Klíč
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(selectedProvider.tokenLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button(action: { isHelpExpanded.toggle() }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "questionmark.circle")
                                        Text("Kde to najdu?")
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack {
                                if isTokenVisible {
                                    TextField(selectedProvider.tokenPlaceholder, text: $token)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                } else {
                                    SecureField(selectedProvider.tokenPlaceholder, text: $token)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                }

                                // Tlačítko zobrazení / skrytí tokenu
                                Button(action: { isTokenVisible.toggle() }) {
                                    Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(isTokenVisible ? "Skrýt token" : "Zobrazit token")

                                // Tlačítko Vložit ze schránky
                                Button(action: {
                                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                                        token = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.on.clipboard")
                                        Text("Vložit")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Vložit ze schránky Macu")
                            }

                            if isHelpExpanded {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedProvider.tokenHelp)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(6)
                                .transition(.opacity)
                            }
                        }
                    }

                    // Výsledek testu
                    if let result = testResult {
                        Text(result)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(result.contains("Úspěch") ? .green : .red)
                    }
                }
            }

            Spacer()

            // Spodní tlačítka
            HStack {
                Button(action: testConnection) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Otestovat")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(effectiveToken.isEmpty || isTesting)

                Spacer()

                Button("Zrušit", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                Button(action: saveAccount) {
                    Text(accountToEdit == nil ? "Uložit účet" : "Aktualizovat")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || effectiveToken.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 400, height: 520)
        .onAppear {
            if title.isEmpty {
                title = selectedProvider.displayName
            }
        }
    }

    private func chooseProfile() {
        let panel = NSOpenPanel()
        panel.title = "Vybrat přihlašovací profil — \(selectedProvider.displayName)"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            profilePath = url.standardizedFileURL.path
            testResult = nil
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let testCred = AccountCredential(
            provider: selectedProvider,
            title: title,
            token: effectiveToken,
            profilePath: selectedProfilePath
        )

        Task {
            let status: LimitStatus
            switch testCred.provider {
            case .chatgpt:
                status = await ChatGPTService.shared.fetchLimitStatus(for: testCred)
            case .claude:
                status = await ClaudeService.shared.fetchLimitStatus(for: testCred)
            case .gemini:
                status = await GeminiService.shared.fetchLimitStatus(for: testCred)
            case .perplexity:
                status = await PerplexityService.shared.fetchLimitStatus(for: testCred)
            }

            await MainActor.run {
                isTesting = false
                guard selectedProvider == testCred.provider, effectiveToken == testCred.token,
                    selectedProfilePath == testCred.profilePath
                else {
                    testResult = "Nastavení se změnilo. Otestujte nové přihlašovací údaje znovu."
                    return
                }
                if status.healthState == .error {
                    testResult = "Chyba spojení: \(status.statusDescription)"
                } else if status.healthState == .unavailable {
                    testResult = "Kvóta nedostupná: \(status.statusDescription)"
                } else if status.isDemo {
                    testResult = "Demo: simulovaná data, spojení nebylo ověřeno."
                } else {
                    testResult = "Úspěch! \(status.statusDescription)"
                }
            }
        }
    }

    private func saveAccount() {
        if let existing = accountToEdit {
            var updated = existing
            updated.provider = selectedProvider
            updated.title = title
            updated.token = effectiveToken
            updated.profilePath = selectedProfilePath
            guard monitor.updateAccount(updated) else {
                testResult = monitor.storageError
                return
            }
        } else {
            let newAccount = AccountCredential(
                provider: selectedProvider,
                title: title,
                token: effectiveToken,
                profilePath: selectedProfilePath
            )
            guard monitor.addAccount(newAccount) else {
                testResult = monitor.storageError
                return
            }
        }
        onDismiss()
    }
}

struct ProviderSelectButton: View {
    let provider: AIProvider
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : provider.brandColor)

                Text(provider.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? provider.brandColor : Color.primary.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? provider.brandColor : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
