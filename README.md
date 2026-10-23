# AILimiter ⚡

Nativní, minimalistická macOS Menu Bar aplikace pro sledování vytížení a limitů vašich AI účtů (**ChatGPT**, **Claude**, **Google Gemini**, **Perplexity**).

Běží tiše na pozadí v horní systémové liště (`LSUIElement = true` – neobsazuje Dock ani switcher aplikací).

---

## 🌟 Hlavní funkce

- **Umístění vpravo nahoře v menu baru:** Ikona se stavebním indikátorem (zelená = OK, oranžová = blížící se limit >80%, červená = limit vyčerpán).
- **Okamžitý přehled:**
  - Vizuální progress bar pro každý účet.
  - Odpočet do obnovení limitu (např. *Reset za 42m* nebo *19:45*).
  - Tlačítko pro rychlé otevření webu dané služby jedním klikem.
- **Podporované služby a přihlášení:**
  - **ChatGPT / OpenAI:** Web Session Token (`__Secure-next-auth.session-token`) nebo OpenAI API Key (`sk-...`).
  - **Claude (Anthropic):** Claude.ai Session Key (`sessionKey=sk-ant-sid01-...`) nebo Anthropic API Key (`sk-ant-api03-...`).
  - **Google Gemini:** Google AI Studio API Key (`AIza...`) pro sledování kvót (15 RPM / 1500 RPD).
  - **Perplexity:** Perplexity API Key (`pplx-...`) nebo Session Cookie.
- **Zabezpečení a soukromí (App Sandbox):**
  - Aplikace je striktně uzavřena v **Apple App Sandboxu** (`com.apple.security.app-sandbox = true`).
  - **Nulový přístup k souborům:** Aplikace nemá přístup k vašim souborům, dokumentům, ploše, historii prohlížeče ani jiným aplikacím v Macu.
  - Povoleno je výhradně odchozí síťové spojení pro dotazy na AI servery (`com.apple.security.network.client = true`).
- **Izolace chyb a ochrana proti pádům (CrashHandler):**
  - Každý síťový požadavek je striktně izolován a ošetřen v `do-catch` bloku – chyba jednoho účtu neovlivní zbytek.
  - Globální `CrashHandler` odchytává neošetřené výjimky a POSIX signály – pokud by došlo k nečekanému pádu, aplikace je bezpečně zastavena, zobrazí uživateli vysvětlující dialog s chybou a čistě se ukončí, aniž by ovlivnila systém.
- **Bezpečnost:** Tokeny a klíče jsou ukládány přes Apple **Keychain Services**.
- **Systémové notifikace:** Automatické upozornění při 80% vyčerpání, 100% vyčerpání a při následné obnově limitu.
- **Minimální spotřeba zdrojů:** Binárka má méně než 1 MB a spotřebu pouhých ~15 MB RAM (žádný Electron/Chromium).

---

## 🚀 Rychlé spuštění

V terminálu ve složce projektu:

```bash
# Sestavení a okamžité spuštění do menu baru:
make run

# Nebo instalace do /Applications:
make install
```

---

## 🛠️ Architektura projektu

```
ailimiter/
├── Makefile                     # make build / run / install
├── scripts/
│   └── build_app.sh             # Sestavovací skript do AILimiter.app
├── Resources/
│   └── Info.plist               # Konfigurace LSUIElement pro menu bar
└── Sources/
    └── AILimiter/
        ├── App/
        │   ├── main.swift               # Vstupní bod
        │   ├── AppDelegate.swift        # NSApplicationDelegate v accessory módu
        │   └── MenuBarController.swift  # NSStatusItem + NSPopover logika
        ├── Models/
        │   ├── AIProvider.swift         # Definice služeb, barvy, návody
        │   ├── AccountCredential.swift  # Model účtu
        │   └── LimitStatus.swift        # Stav limitu, odpočet, zdraví
        ├── Services/
        │   ├── KeychainManager.swift    # Bezpečné ukládání v Keychain
        │   ├── NotificationService.swift# Systémové macOS notifikace
        │   ├── LimitMonitor.swift       # Orchestrátor a polling timer
        │   └── Providers/
        │       ├── ChatGPTService.swift
        │       ├── ClaudeService.swift
        │       ├── GeminiService.swift
        │       └── PerplexityService.swift
        └── Views/
            ├── PopoverContentView.swift # Hlavní SwiftUI okno
            ├── DashboardView.swift      # Přehled karet
            ├── ProviderCardView.swift   # Karta účtu s progress barem
            ├── SettingsView.swift       # Správa účtů a intervalu
            └── AddAccountSheet.swift    # Přidání/úprava s testem spojení
```
