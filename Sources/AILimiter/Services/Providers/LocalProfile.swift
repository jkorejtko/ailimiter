import Foundation

enum LocalProfile {
    static func selectedFile(for account: AccountCredential) throws -> URL? {
        guard let path = account.profilePath else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw ProfileError.invalidPath }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    static func json(at file: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: file)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProfileError.invalidFormat
        }
        return json
    }

    enum ProfileError: LocalizedError {
        case invalidPath, invalidFormat
        var errorDescription: String? {
            switch self {
            case .invalidPath: return "Vyberte soubor profilu pomocí tlačítka Vybrat soubor."
            case .invalidFormat: return "Profil nemá podporovaný formát JSON."
            }
        }
    }
}
