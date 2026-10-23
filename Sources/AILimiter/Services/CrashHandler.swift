import AppKit
import Foundation

public final class CrashHandler: @unchecked Sendable {
    public static let shared = CrashHandler()

    private init() {}

    public func install() {
        // 1. Záchrana neošetřených výjimek
        NSSetUncaughtExceptionHandler { exception in
            let reasonStr = "Neošetřená systémová výjimka: \(exception.name.rawValue)"
            let detailsStr = exception.reason ?? "Neznámý důvod\n\(exception.callStackSymbols.prefix(5).joined(separator: "\n"))"
            DispatchQueue.main.sync {
                CrashHandler.showFatalAlertAndExit(
                    reason: reasonStr,
                    details: detailsStr
                )
            }
        }

        // 2. Ošetření kritických POSIX signálů (SIGSEGV, SIGABRT, SIGBUS...)
        let signals = [SIGSEGV, SIGABRT, SIGILL, SIGBUS, SIGFPE]
        for sig in signals {
            signal(sig) { signalNumber in
                DispatchQueue.main.sync {
                    CrashHandler.showFatalAlertAndExit(
                        reason: "Kritická chyba procesu (Signál \(signalNumber))",
                        details: "Aplikace zachytila kritický pád a byla bezpečně izolována, aby neovlivnila systém."
                    )
                }
            }
        }
    }

    @MainActor
    public static func showFatalAlertAndExit(reason: String, details: String) {
        let alert = NSAlert()
        alert.messageText = "AILimiter narazil na chybu a byl zastaven"
        alert.informativeText = "\(reason)\n\nDetaily:\n\(details)\n\nAplikace se nyní bezpečně ukončí."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Ukončit AILimiter")
        alert.runModal()
        exit(1)
    }
}
