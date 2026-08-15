# Research Apple Platform Constraints

Type: research
Status: resolved

## Question

Using first-party Apple documentation, what macOS, iOS, and iPadOS constraints affect background mail synchronization, secure credential storage, local search/indexing, inter-process agent access, cross-device settings sync, notifications, and App Store distribution for a device-first MailGent v1?

## Answer

**Background sync:** `BGAppRefreshTask` / `BGProcessingTask` are iOS/iPadOS/Catalyst — **not native macOS**. Mac v1 needs consented process lifetime (`SMAppService` helpers) and/or push wake; MAS forbids auto-launch without consent (2.4.5(iii)). iOS foresight: ~30s refresh windows; silent background push OK for email-like apps but **> ~3/hour** is rate-limited. Network Extension Local Push is a restricted local-SSID entitlement — wrong tool for normal internet mail sync.

**Credentials:** OAuth tokens → **Keychain** (+ accessibility / biometrics). Secure Enclave protects generated P-256 keys only — not a vault for refresh-token strings. Use **ASWebAuthenticationSession**.

**Search:** Private on-device Core Spotlight / in-app FTS; indexes stay on-device and are not synced by Apple. Full-body Spotlight donation widens exposure. macOS File Import extensions do not work — importer plugins for custom files.

**Agent IPC:** Sandboxed **XPC**, App Group UNIX-domain sockets, or entitled localhost server (`network.server`). Apple provides transport, not identity/scopes/audit. MAS requires App Sandbox; agent data sharing needs explicit user permission (5.1.2).

**Settings sync:** `NSUbiquitousKeyValueStore` (≤1 MB, App Store required, no secrets) or CloudKit — not mailbox content.

**Notifications:** Local `UNUserNotificationCenter` (macOS 10.14+) for agent events; no sensitive content in remote push; push not required for core function.

**Distribution / Mail:** Choose MAS (sandbox) vs Developer ID + notarization early. Nutrition labels: on-device-only mail need not be “collected”; off-device may declare Emails. MailKit extends Apple Mail; `mailto:`/MessageUI for handoff — no API to read Mail’s store. Skip default-mail-client entitlement for companion v1.

Full findings (cited): [../research/apple-platform-constraints.md](../research/apple-platform-constraints.md)
