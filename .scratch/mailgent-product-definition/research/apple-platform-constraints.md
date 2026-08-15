# Research: Apple Platform Constraints for Device-First MailGent v1

**Question:** Using first-party Apple documentation, what macOS, iOS, and iPadOS constraints affect background mail synchronization, secure credential storage, local search/indexing, inter-process agent access, cross-device settings sync, notifications, and App Store distribution for a device-first MailGent v1?

**Access date for all citations unless noted:** 2026-08-15  
**Platforms in scope:** macOS (v1), iOS / iPadOS (foresight)  
**Out of scope:** Replacing Apple Mail as daily client; built-in AI; Microsoft 365/Exchange; Proton

---

## 1. Decision-oriented summary

| Topic | Confirmed constraint for MailGent v1 |
| --- | --- |
| Background sync (macOS) | **BGAppRefreshTask / BGProcessingTask are not native macOS APIs** (documented for iOS, iPadOS, Mac Catalyst, tvOS, visionOS). macOS sync must rely on **user-visible / consented** process lifetime: running app, **SMAppService** helpers (LaunchAgent / daemon / login item on macOS 13+), or push wake where applicable. Mac App Store forbids auto-launch / leftover processes **without consent** (Guideline 2.4.5(iii)). |
| Background sync (iOS/iPadOS) | Use **BGAppRefreshTask** (short refresh; system gives **≤ ~30s**), **BGProcessingTask** (longer; idle/charging; interruptible), and/or **silent background push** (`content-available`). Apple’s own strategy doc cites **email apps** as a background-push example. Pushing **> ~3 background pushes/hour** triggers rate limiting. Network Extension **Local Push Connectivity** is a restricted-entitlement, local-SSID / APNs-replacement path — not a general internet mail sync substitute. |
| Credentials | Store OAuth tokens / secrets in **Keychain Services**. Tune **`kSecAttrAccessible`** and optional **`SecAccessControl`** (biometrics / passcode / app password). **Secure Enclave** protects *generated* NIST P-256 private keys (signing / ECDH) — it does **not** store arbitrary OAuth refresh tokens as SE-resident blobs. Share tokens across app targets via **Keychain Sharing** / **App Groups**. Use **ASWebAuthenticationSession** for OAuth UX (macOS 10.15+). |
| Local search | Prefer **private, on-device Core Spotlight indexes** (`CSSearchableIndex`) and/or an **in-app** FTS index. Core Spotlight indexes stay on-device; Apple docs state devices **do not share indexed data with Apple** or sync indexes between devices. For sensitive content use a **named secure index**. On macOS, Spotlight **File Import extensions do not provide functionality** — custom file types need a **Spotlight importer plugin**. Indexing mail into system Spotlight increases discoverability but also surface area outside MailGent UI. |
| Agent IPC (macOS) | Feasible surfaces: **XPC** (in-bundle XPC service or peer via App Group), **App Groups** (Mach / XPC / POSIX shm / **UNIX domain sockets** between sandboxed peers), **`com.apple.security.network.server` + client** for TCP localhost (sandboxed). Mac App Store requires **App Sandbox**. MCP-style local stdio/HTTP is a **product transport**; sandbox + review still apply. Identity, scopes, and auditability are **not** provided by Apple IPC primitives — MailGent must implement them. |
| Settings sync | **`NSUbiquitousKeyValueStore`**: settings/config only; **≤1024 keys**, **1 MB** total; **App Store / Mac App Store distribution required**; **do not store secrets** (disk unencrypted). Prefer Keychain for credentials. **CloudKit / CKSyncEngine** for richer preference graphs (requires CloudKit + remote-notification entitlements); keep **mailbox content out** of iCloud for device-first v1. |
| Notifications | **`UNUserNotificationCenter`** local notifications are supported on **macOS 10.14+** and iOS/iPadOS. Request authorization; keep agent-event alerts **local** and related to app functionality (Guidelines **2.5.16**, **4.5.4**). Do **not** put sensitive mail content in remote push payloads; push must not be required for core function. |
| Distribution | **Mac App Store:** mandatory sandbox, self-contained bundle, consented login items only, MAS-only updates. **Developer ID + notarization:** required for Gatekeeper outside MAS (Hardened Runtime, etc.); notarization ≠ App Review. Privacy: **nutrition label** + **privacy policy**; on-device-only data is **not** “collected”; if anything leaves device declare types (incl. **Emails or Text Messages**). **Default Mail client** entitlement (`com.apple.developer.mail-client`) is **iOS/iPadOS/visionOS** and unnecessary for a companion. |
| Apple Mail companion surfaces | **MailKit** (macOS 12+): extensions **inside** Apple Mail (blockers, download actions, compose session, crypto) — not a substitute for MailGent’s own mailbox cache. **MessageUI** / **`mailto:`**: compose / handoff to Mail on iOS/iPadOS (Mac Catalyst). No documented public API grants third-party apps arbitrary read access to Apple Mail’s store. Avoid looking like Apple Mail (Guideline **5.2.5**). |

---

## 2. Background execution and mail-like sync

### 2.1 Background Tasks framework (iOS / iPadOS / Catalyst)

- **`BGAppRefreshTask`**: short background refresh for small content updates. Platforms in Apple’s API reference: **iOS 13+, iPadOS 13+, Mac Catalyst 13.1+, tvOS, visionOS** — **not listed for native macOS**. Requires the Background Modes / refresh capability. ([BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask))
- **`BGProcessingTask`**: longer maintenance / data processing while backgrounded; may run for minutes but **can be interrupted**; runs when the device is **idle**; terminated when the user starts using the device. Same platform set as above (no native macOS). ([BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask))
- **`BGTaskScheduler`**: register, schedule, and run these tasks while suspended. ([BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler))
- Strategy guidance ([Choosing Background Strategies for Your App](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)):
  - Finite foreground→background work: begin a background task; limited time; call end before expiry or the system terminates the app.
  - Heavy deferred work: `BGProcessingTask` (e.g. overnight while charging).
  - Short periodic refresh: `BGAppRefreshTask` / `BGAppRefreshTaskRequest`; system decides launch time; **up to ~30 seconds**; must call setTaskCompleted or the app is terminated.
  - **Background pushes**: silent wake (`content-available: 1` without alert/sound/badge). Explicit example: *“an email app that processes incoming mail without alerting the user.”* System may delay delivery; **≤ ~30 seconds** of work; call the completion handler promptly. **More than three background pushes per hour** → rate limitations.
  - User-visible alert after download: **Notification Service Extension** pattern (email example given).
- Sample / WWDC pointer: *Refreshing and Maintaining Your App Using Background Tasks* is associated with **WWDC 2019 session Advances in App Background Execution**. ([Refreshing and Maintaining…](https://developer.apple.com/documentation/backgroundtasks/refreshing-and-maintaining-your-app-using-background-tasks); [WWDC19 session 707](https://developer.apple.com/videos/play/wwdc2019/707/))
- **`UIBackgroundModes`**: Info.plist key for background services; configure via Background Modes capability. Platforms listed: iOS, iPadOS, visionOS, watchOS (not macOS). ([UIBackgroundModes](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes))
- App Review: multitasking apps may only use background services for **intended purposes** (VoIP, audio, location, task completion, local notifications, etc.). ([App Store Review Guidelines 2.5.4](https://developer.apple.com/app-store/review/guidelines/))

### 2.2 macOS process lifetime and helpers

- **Service Management / `SMAppService`** (macOS 13+): register and control helper executables that live **inside the app’s main bundle** — LaunchAgent, daemon, and login-item styles — replacing older `SMLoginItemSetEnabled` / plist-install patterns. ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice); [Service Management](https://developer.apple.com/documentation/servicemanagement))
- Mac App Store: apps **may not auto-launch or have other code run automatically at startup or login without consent**, nor spawn processes that continue after quit **without consent**. ([Guidelines 2.4.5(iii)](https://developer.apple.com/app-store/review/guidelines/))
- Implication: always-on IMAP IDLE / poller on Mac is a **consent + UX** problem under MAS, and an **architecture** problem under sandbox (see §5).

### 2.3 Network Extension / Local Push Connectivity

- Network Extension covers VPN, content filters, DNS proxy, relays, etc. — not a general-purpose mail sync API. ([Network Extension](https://developer.apple.com/documentation/networkextension))
- **Local push connectivity**: persistent connection when on configured Wi‑Fi SSIDs as an **APNs replacement on restricted local networks**; requires **`com.apple.developer.networking.networkextension`** with the app-push-provider value, requested from Apple; intended for small alerts / VoIP-like wakes. Use APNs when unrestricted internet is available. ([Local push connectivity](https://developer.apple.com/documentation/networkextension/local-push-connectivity); [Network Extensions Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension))
- VPN apps have additional Review rules (5.4) — irrelevant unless MailGent misuses NEVPNManager. ([Guidelines 5.4](https://developer.apple.com/app-store/review/guidelines/))

### 2.4 Push entitlements

- Remote notifications: `aps-environment` / macOS `com.apple.developer.aps-environment`. ([APS Environment](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment); [APS Environment (macOS)](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.aps-environment))
- Silent background push sample (iOS/iPadOS/Catalyst): [Implementing Background Push Notifications](https://developer.apple.com/documentation/usernotifications/implementing-background-push-notifications)

### 2.5 Implications for MailGent

| Platform | Practical sync model for device-first v1 |
| --- | --- |
| macOS | Foreground / docked companion + **user-consented** helper (`SMAppService`) for polling/IDLE; optional silent push **if** a minimal wake backend exists (tensions with “no mailbox content in cloud”). Do not design as if `BGAppRefreshTask` exists on AppKit macOS. |
| iOS/iPadOS (later) | Combine `BGAppRefreshTask`, occasional `BGProcessingTask` for index maintenance, and silent push rate-budget; treat 30s windows and rate limits as hard product constraints. |

---

## 3. Secure credential storage

### 3.1 Keychain Services

- Keychain stores **small secrets** (passwords, keys, certificates, short notes) in an encrypted database. ([Keychain services](https://developer.apple.com/documentation/security/keychain-services))
- Accessibility: set `kSecAttrAccessible` (and ThisDeviceOnly variants) relative to lock state and backup migration; prefer the **most restrictive** option that still works. Background access while locked requires a more permissive accessibility choice (security tradeoff). ([Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility))
- Stronger gates: `SecAccessControl` + flags for biometrics / device passcode / application password before retrieving an item. ([Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility); [Access Control Lists](https://developer.apple.com/documentation/security/access-control-lists))
- Sharing within a team: **Keychain Sharing** capability / access groups; app IDs are default private groups; optional App Group identifiers also participate in keychain access groups (iOS 8+ pattern documented). ([Sharing access to keychain items among a collection of apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps); [Keychain Access Groups Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups))

### 3.2 Secure Enclave

- Extra protection for **private keys**: plaintext key never leaves the SE; app only gets operation outputs (signatures / ECDH). ([Protecting keys with the Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave))
- Limits: hardware support (A7+ iPhone; Mac with Touch Bar+Touch ID or **Apple silicon M1+**); **NIST P-256 only**; **cannot import preexisting keys** — keys must be generated in the SE. Suitable for app-owned signing / wrapping keys, **not** as a drop-in vault for provider-issued OAuth refresh token strings.
- LocalAuthentication coordinates biometrics with the SE; app never receives biometric templates. ([Local Authentication](https://developer.apple.com/documentation/localauthentication))

### 3.3 OAuth session UX

- **`ASWebAuthenticationSession`**: system-mediated browser auth; macOS opens default browser (if supporting) or Safari; callback isolated to the calling app’s session. Platforms include **macOS 10.15+**, iOS 12+. ([ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession))

### 3.4 Implications for MailGent

- Put Gmail/Yahoo tokens in Keychain with tight accessibility; consider `userPresence` for high-risk operations (send approval), not necessarily every background sync read.
- Optional SE-backed key to encrypt an on-disk mailbox cache — product crypto design, within SE algorithm limits.
- Never put refresh tokens in `NSUbiquitousKeyValueStore` or plaintext app-group files.

---

## 4. Local search and indexing

### 4.1 Core Spotlight

- Framework purpose: index app content for **Spotlight and Safari**, and search within the app. Platforms include **macOS 10.13+**, iOS 9+, iPadOS, Mac Catalyst, visionOS. ([Core Spotlight](https://developer.apple.com/documentation/corespotlight))
- Indexes are **on-device** and **private to the device owner**; docs state devices **don’t share indexed data with Apple** or synchronize that indexed data across devices. ([Core Spotlight](https://developer.apple.com/documentation/corespotlight))
- Indexing guidance: index content people care about (explicitly includes **messages they sent and received**); keep indexes current; use named indexes; for more sensitive data use `CSSearchableIndex(name:protectionClass:)`. Default index is for prototyping only. ([Adding your app’s content to Spotlight indexes](https://developer.apple.com/documentation/corespotlight/adding-your-app-s-content-to-spotlight-indexes); [CSSearchableItem](https://developer.apple.com/documentation/corespotlight/cssearchableitem))
- macOS caveat: **Spotlight File Import extensions don’t provide functionality on macOS**; use a **Spotlight importer plugin** for custom file types. ([Core Spotlight](https://developer.apple.com/documentation/corespotlight); archived [Spotlight Importer Programming Guide](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/MDImporters/MDImporters.html))
- In-app query APIs: `CSSearchQuery` / `CSUserQuery`. ([Searching for information in your app](https://developer.apple.com/documentation/corespotlight/searching-for-information-in-your-app); [Building a search interface for your app](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app))

### 4.2 App Intents (foresight / Apple surfaces)

- App Intents expose actions/entities to Siri, Shortcuts, Spotlight, Widgets, Apple Intelligence — **system** experiences, not third-party agent grants. ([Getting started with the App Intents framework](https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework))

### 4.3 Implications for MailGent

- Device-first full-text search can be **entirely private** (in-app index) or **also** donated to Spotlight for discoverability.
- Donating full message bodies to Spotlight expands the trust boundary (system search UI, other Apple features that consume indexes). Prefer metadata-only Spotlight donation + private FTS for bodies if minimizing exposure.
- Cross-device search index sync is **not** provided by Core Spotlight; would require app-owned sync (conflicts with device-first mailbox content policy if using iCloud).

---

## 5. Inter-process agent access (XPC, App Groups, localhost, sandbox)

### 5.1 XPC

- Low-level IPC; modern listener/session APIs; XPC Service target in Xcode; service name typically the XPC bundle ID; listener accepts/rejects sessions. Platforms include **macOS 10.10+** (and limited iOS versions for some APIs). ([XPC](https://developer.apple.com/documentation/xpc); [Creating XPC services](https://developer.apple.com/documentation/xpc/creating-xpc-services))
- Higher-level: `NSXPCConnection` bidirectional channel. ([NSXPCConnection](https://developer.apple.com/documentation/foundation/nsxpcconnection))

### 5.2 App Groups

- Apps in a group share a container, can share keychain access groups, and may use **IPC including Mach, XPC, POSIX semaphores/shared memory, and UNIX domain sockets**. On macOS, App Groups enable IPC between sandboxed apps or sandboxed ↔ nonsandboxed. ([App Groups Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups))
- External AI agents **not signed by MailGent’s team** are **outside** the App Group trust model. They need a deliberate bridge (XPC endpoint MailGent exposes, localhost server MailGent runs, or stdio launched by the user).

### 5.3 Network entitlements (localhost servers)

- Sandboxed macOS apps need **`com.apple.security.network.client`** to open outgoing connections (including to the same machine) and **`com.apple.security.network.server`** to listen for incoming connections. ([network.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client); [network.server](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server))
- App Sandbox is **required for Mac App Store** distribution. ([App Sandbox](https://developer.apple.com/documentation/security/app-sandbox); [App Sandbox Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox); [Guidelines 2.4.5(i)](https://developer.apple.com/app-store/review/guidelines/))

### 5.4 Review / privacy interaction with agents

- Apps must implement appropriate security for user information and prevent unauthorized third-party access. ([Guidelines 1.6](https://developer.apple.com/app-store/review/guidelines/))
- Sharing personal data with third parties (including **third-party AI**) requires **clear disclosure and explicit permission**. ([Guidelines 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/))
- Hidden / undocumented features are forbidden — agent IPC must be explainable in Review notes and UX. ([Guidelines 2.3.1](https://developer.apple.com/app-store/review/guidelines/))
- Guideline **4.7** (mini apps / chatbots / plug-ins): if MailGent hosts third-party software inside the app, additional rules apply (privacy, indexing of software, age ratings). Local external agents connecting via IPC are a different shape, but App Review may still scrutinize “agent platform” behavior.

### 5.5 Implications for MailGent

- **Best MAS-aligned pattern:** MailGent (sandboxed) hosts an **XPC service or UNIX-domain socket bound to an App Group / documented localhost port**, authenticates clients with MailGent-issued credentials, enforces scopes, writes an append-only audit log.
- **stdio MCP** launched by Cursor/Claude as a child process: fits Developer ID / non-MAS more easily; under MAS, downloading/executing new code or escaping the container is heavily restricted ([Guidelines 2.5.2](https://developer.apple.com/app-store/review/guidelines/)). Prefer in-bundle helper + IPC.
- Apple does **not** provide agent identity / scope / audit primitives — those remain product requirements on top of XPC/network.

---

## 6. Cross-device settings sync (not mailbox content)

### 6.1 iCloud Key-Value Store

- `NSUbiquitousKeyValueStore` syncs a small key-value dictionary via the user’s Apple Account across devices. ([NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore))
- **Must** distribute via App Store or Mac App Store and enable the iCloud Key-Value Store entitlement/capability.
- Limits: **1024 keys**, **1 MB** total value storage, **1 MB** max per value, **128** UTF-16 chars max key length.
- **Do not store personal or sensitive information** — stored on disk **unencrypted**; use Keychain instead.

### 6.2 CloudKit

- `CKContainer` / CloudKit for structured iCloud data. ([CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer); [CloudKit](https://developer.apple.com/documentation/cloudkit))
- `CKSyncEngine` manages push/pull of record changes; schedule is opportunistic (battery, network, signed-in account); requires **CloudKit** and **Remote notifications** entitlements; not for public DB. ([CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9))

### 6.3 Implications for MailGent

- Sync **policy preferences, notification severity toggles, non-secret UI settings** via KVS or CloudKit.
- Keep **mailbox cache, search index, OAuth tokens, audit logs, agent grants** on-device (aligns with nutrition-label “not collected if never leaves device” — see §8).

---

## 7. Notifications

- Central API: **`UNUserNotificationCenter`** — authorization, categories, scheduling, delivered notification management. macOS **10.14+**, iOS 10+. ([UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter); [User Notifications](https://developer.apple.com/documentation/usernotifications))
- Local scheduling: content + calendar/time/location triggers; remains active until fired or cancelled. ([Scheduling a notification locally from your app](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app))
- Review constraints:
  - Notifications must relate to the app’s content/functionality. ([2.5.16](https://developer.apple.com/app-store/review/guidelines/))
  - Push must **not** be required for the app to function; must **not** send **sensitive personal or confidential information**; marketing push needs explicit opt-in + opt-out. ([4.5.4](https://developer.apple.com/app-store/review/guidelines/))
- Monetizing built-in capabilities such as Push Notifications is forbidden. ([4.10](https://developer.apple.com/app-store/review/guidelines/))

### Implications for MailGent

- Optional **local** alerts for approval-needed / agent events match first-party APIs and Guidelines.
- Avoid embedding subjects/bodies in **remote** push payloads; prefer wake + local redacted notification, or local-only notifications when the Mac app/helper is running.

---

## 8. App Store distribution, privacy labels, notarization

### 8.1 Mac App Store vs Developer ID notarization

| Path | What Apple docs/guidelines require |
| --- | --- |
| Mac App Store | Sandbox; follow filesystem rules; Xcode packaging; no auto-start without consent; no root; MAS updates only; etc. ([Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/)) |
| Outside MAS (Developer ID) | **Notarization** scans for malware / signing issues; **not** App Review. Required for many Developer ID distributions (esp. post–macOS Catalina rules cited in docs). Needs Hardened Runtime, secure timestamp, Developer ID cert, etc. MAS apps are **not** required to notarize separately because submission already includes equivalent checks. ([Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)) |

### 8.2 Privacy nutrition labels and manifests

- App privacy details on the product page are **required** for App Store submission; declare data you or third-party partners **collect** (transmitted off device and retained longer than needed to service a real-time request). ([App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/))
- Explicit data type: **Emails or Text Messages** (subject, sender, recipients, contents).
- **On-device-only** processing that never leaves the device is **not “collected”** and need not be disclosed on the label. (Same page, “Additional guidance.”)
- Privacy policy required in metadata and in-app. ([Guidelines 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/))
- Privacy manifests (`PrivacyInfo.xcprivacy`) record collected data types and required-reason API uses. ([Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files))

### 8.3 Email-client-specific entitlement (not v1 companion)

- `com.apple.developer.mail-client`: managed entitlement so an app can be the **default email client** on **iOS / iPadOS / visionOS**; must handle `mailto:`, send to any recipient, receive from any sender. Request via developer account form. **Not required** for a companion that is not the default MUA. ([com.apple.developer.mail-client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.mail-client))

### 8.4 Other Review hotspots for MailGent

- **5.2.2** Third-party services: must be permitted under Gmail/Yahoo terms; authorization on request. ([Guidelines](https://developer.apple.com/app-store/review/guidelines/))
- **5.2.5** Don’t create an app confusingly similar to Apple apps (Mail, etc.).
- **4.2.3(i)** App should work on its own without requiring installation of another app — frame MailGent as a complete companion (accounts, search, approvals, agents) that *optionally* deep-links to Mail, not as a hollow shell that requires Mail for core value.
- **2.1** Demo account / credentials for Review if login required.
- **5.1.2** Explicit permission before sharing data with third-party AI.

---

## 9. MailKit, MessageUI, and “open in Apple Mail”

### 9.1 MailKit (macOS 12+)

- MailKit lets you ship a **Mail app extension** that customizes **Apple Mail**: content blocking, actions on download, compose-session validation/UI/headers, message security (sign/encrypt). Entry: `MEExtension`. ([MailKit](https://developer.apple.com/documentation/mailkit); [MEExtension](https://developer.apple.com/documentation/mailkit/meextension); sample [Build Mail App Extensions](https://developer.apple.com/documentation/mailkit/build-mail-app-extensions) associated with WWDC21)
- Useful if MailGent later wants in-Mail hooks; **does not** give MailGent a supported API to read the user’s full Mail database as a third-party process.

### 9.2 MessageUI / mailto

- **`MFMailComposeViewController`**: in-app compose UI on iOS/iPadOS/Catalyst; queues through the user’s Mail outbox; alternate path is opening a **`mailto:`** URL to the built-in Mail app. ([MFMailComposeViewController](https://developer.apple.com/documentation/messageui/mfmailcomposeviewcontroller))
- Check `canSendMail` before presenting.

### 9.3 Implications for MailGent

- “Open in Apple Mail” for v1 should be designed around **user-visible handoff** (`mailto:` / documented URL opening / “copy link”) rather than undocumented Mail internals.
- A MailKit extension is optional adjacency, not the agent-safe companion core.
- Do not claim Apple-Mail-store parity without a first-party API — there isn’t one in the cited docs.

---

## 10. Concrete v1 constraints checklist

| # | Constraint |
| --- | --- |
| A1 | Do not plan native-macOS sync on `BGAppRefreshTask` / `BGProcessingTask`; those APIs are Catalyst/iOS-family. |
| A2 | Any always-on Mac helper must use **consented** `SMAppService` / login-item flows under MAS Guideline 2.4.5(iii). |
| A3 | iOS/iPadOS foresight: budget **~30s** refresh windows and **≤ ~3 silent pushes/hour** before throttling. |
| A4 | Store OAuth tokens in **Keychain**; use SE only for generated P-256 keys / wrapping, not as an OAuth token dump. |
| A5 | Prefer private on-device search; treat full-body Spotlight donation as an explicit privacy tradeoff. |
| A6 | Agent access = sandboxed **XPC / App Group UDS / entitled localhost server** + MailGent-owned authZ/audit; declare AI data sharing under 5.1.2. |
| A7 | Settings sync via KVS/CloudKit only; **no** mailbox bodies/tokens in iCloud KVS. |
| A8 | Agent notifications: **local** `UNUserNotificationCenter`; no sensitive content in remote pushes; push not required for core use. |
| A9 | Choose **MAS (sandbox)** vs **Developer ID + notarization** early; both constrain agent packaging differently. |
| A10 | Privacy label: on-device-only mail processing need not be declared as collected; anything leaving device may require **Emails or Text Messages**. |
| A11 | Skip default-mail-client entitlement for companion v1; use MessageUI/`mailto:`/MailKit only as handoff/extension surfaces. |
| A12 | Network Extension Local Push / VPN entitlements are the wrong tool for normal Gmail/Yahoo internet sync. |

---

## 11. Open risks / unknowns

| Risk | Why it remains open |
| --- | --- |
| Exact MAS acceptance of localhost MCP / always-on agent sockets | Entitlements exist (`network.server`), but App Review interpretation of “agent platform,” 4.7, and 2.5.2 for companion binaries is case-by-case — not fully determined by docs alone. |
| Silent push without a content-aware backend | Gmail-style Pub/Sub needs a server; pure device-first conflicts with APNs wake-from-cloud unless the push payload stays opaque and non-mail-content. |
| Documented deep link to a *specific* existing Apple Mail message | First-party docs strongly cover `mailto:` compose and MailKit *inside* Mail; a stable public message-id URL API was **not** confirmed in the sources below. |
| Background Keychain access vs lock state | Docs allow relaxing accessibility for locked-device background access — security vs sync reliability tradeoff needs product decision. |
| Non–Apple-silicon Mac Secure Enclave | SE key protection requires listed hardware; Intel Macs without Touch ID SE support cannot use the same key isolation. |
| iOS agent IPC foresight | iOS sandbox is stricter; third-party local agents comparable to macOS Cursor/stdio are far less realistic — expect different agent topology on phone/tablet. |

---

## 12. Source index

| Source | URL | Accessed |
| --- | --- | --- |
| Background Tasks | https://developer.apple.com/documentation/backgroundtasks | 2026-08-15 |
| BGAppRefreshTask | https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask | 2026-08-15 |
| BGProcessingTask | https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask | 2026-08-15 |
| BGTaskScheduler | https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler | 2026-08-15 |
| Choosing Background Strategies | https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app | 2026-08-15 |
| Refreshing and Maintaining… | https://developer.apple.com/documentation/backgroundtasks/refreshing-and-maintaining-your-app-using-background-tasks | 2026-08-15 |
| WWDC19 Advances in App Background Execution | https://developer.apple.com/videos/play/wwdc2019/707/ | 2026-08-15 |
| UIBackgroundModes | https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes | 2026-08-15 |
| SMAppService | https://developer.apple.com/documentation/servicemanagement/smappservice | 2026-08-15 |
| Service Management | https://developer.apple.com/documentation/servicemanagement | 2026-08-15 |
| Network Extension | https://developer.apple.com/documentation/networkextension | 2026-08-15 |
| Local push connectivity | https://developer.apple.com/documentation/networkextension/local-push-connectivity | 2026-08-15 |
| Network Extensions Entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension | 2026-08-15 |
| APS Environment | https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment | 2026-08-15 |
| APS Environment (macOS) | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.aps-environment | 2026-08-15 |
| Background Push sample | https://developer.apple.com/documentation/usernotifications/implementing-background-push-notifications | 2026-08-15 |
| Keychain services | https://developer.apple.com/documentation/security/keychain-services | 2026-08-15 |
| Restricting keychain accessibility | https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility | 2026-08-15 |
| Sharing keychain items | https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps | 2026-08-15 |
| Keychain Access Groups | https://developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups | 2026-08-15 |
| Protecting keys with Secure Enclave | https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave | 2026-08-15 |
| Local Authentication | https://developer.apple.com/documentation/localauthentication | 2026-08-15 |
| ASWebAuthenticationSession | https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession | 2026-08-15 |
| Core Spotlight | https://developer.apple.com/documentation/corespotlight | 2026-08-15 |
| Adding content to Spotlight indexes | https://developer.apple.com/documentation/corespotlight/adding-your-app-s-content-to-spotlight-indexes | 2026-08-15 |
| CSSearchableItem | https://developer.apple.com/documentation/corespotlight/cssearchableitem | 2026-08-15 |
| Searching in your app | https://developer.apple.com/documentation/corespotlight/searching-for-information-in-your-app | 2026-08-15 |
| App Intents getting started | https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework | 2026-08-15 |
| XPC | https://developer.apple.com/documentation/xpc | 2026-08-15 |
| Creating XPC services | https://developer.apple.com/documentation/xpc/creating-xpc-services | 2026-08-15 |
| NSXPCConnection | https://developer.apple.com/documentation/foundation/nsxpcconnection | 2026-08-15 |
| App Groups Entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups | 2026-08-15 |
| network.client | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client | 2026-08-15 |
| network.server | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server | 2026-08-15 |
| App Sandbox | https://developer.apple.com/documentation/security/app-sandbox | 2026-08-15 |
| App Sandbox Entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox | 2026-08-15 |
| NSUbiquitousKeyValueStore | https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore | 2026-08-15 |
| CloudKit | https://developer.apple.com/documentation/cloudkit | 2026-08-15 |
| CKContainer | https://developer.apple.com/documentation/cloudkit/ckcontainer | 2026-08-15 |
| CKSyncEngine | https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9 | 2026-08-15 |
| UNUserNotificationCenter | https://developer.apple.com/documentation/usernotifications/unusernotificationcenter | 2026-08-15 |
| Scheduling local notifications | https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app | 2026-08-15 |
| Notarizing macOS software | https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution | 2026-08-15 |
| App Store Review Guidelines | https://developer.apple.com/app-store/review/guidelines/ | 2026-08-15 |
| App privacy details | https://developer.apple.com/app-store/app-privacy-details/ | 2026-08-15 |
| Privacy manifest files | https://developer.apple.com/documentation/bundleresources/privacy-manifest-files | 2026-08-15 |
| mail-client entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.mail-client | 2026-08-15 |
| MailKit | https://developer.apple.com/documentation/mailkit | 2026-08-15 |
| MEExtension | https://developer.apple.com/documentation/mailkit/meextension | 2026-08-15 |
| Build Mail App Extensions | https://developer.apple.com/documentation/mailkit/build-mail-app-extensions | 2026-08-15 |
| MFMailComposeViewController | https://developer.apple.com/documentation/messageui/mfmailcomposeviewcontroller | 2026-08-15 |
| Managing app life cycle (iOS) | https://developer.apple.com/documentation/uikit/managing-your-app-s-life-cycle | 2026-08-15 |
