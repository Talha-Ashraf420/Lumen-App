# Phone-to-TV account setup

## User flow

1. TV login (also reached from Profile → Add service): **Connect using phone**.
2. Phone login or Profile → Playback & library: **Set up a TV** → **Scan TV QR**.
3. Choose one saved non-demo service, or enter provider credentials / a playlist URL.
4. Tap **Send account to TV**. Compare the six-digit code on both screens.
5. On the TV choose **Approve and connect**. Reject is focused by default.
6. The normal TV login flow authenticates with the provider before saving the account.

This copies an account, not favorites, progress, downloads or viewing profiles.
New account details typed for pairing are not saved on the phone. Existing phone
accounts are unchanged. Manual TV login remains available. Pairing entry points
are restricted to actual Android TV receivers and Android/iOS phone senders;
desktop navigation is unchanged.

## Transport and threat model

- No cloud account, relay, analytics, mDNS discovery, or third-party QR service.
- TV binds an ephemeral HTTP listener to one private IPv4 interface, not all
  interfaces. Multiple eligible interfaces get a selector. Guest-network client
  isolation, firewalls, VPN routing and IPv6-only networks may prevent pairing.
- The QR contains a version, private IPv4 address, ephemeral port, random
  128-bit session ID, 256-bit random pairing secret and a three-minute expiry.
  It contains **no provider credentials**, but is itself sensitive. Do not log,
  share, persist, or include a live QR in diagnostics or store screenshots.
- AES-256-GCM from `cryptography` encrypts and authenticates requests and
  responses. Every envelope gets a random 96-bit nonce. Associated data binds
  protocol version, session and direction. The key never travels over HTTP.
- Status replies echo fresh authenticated request challenges and the offer ID;
  stale/replayed or forged replies cannot confirm approval on the phone.
- Only one offer ID is accepted. Retrying that offer reports its existing state
  without replacing credentials or applying the account twice. Rejection is
  terminal until a fresh QR is generated. No storage or provider requests happen
  in the receiver service itself.
- Six digits are a visual comparison code, **not** the encryption key or a
  standalone authentication password. Someone with physical visibility of the
  QR can submit an offer; the user must verify the matching code and provider
  host before approval. A hostile local peer can deny service; this protocol
  does not claim to prevent LAN denial-of-service attacks.
- HTTP bodies have size and total read-time limits; concurrency and invalid
  request counts are bounded. Cross-origin browser requests and redirects are
  rejected. QR parsing rejects DNS names, public/link-local/loopback addresses,
  ambiguous IPv4 spelling, duplicate fields and expired tickets. Loopback is
  enabled explicitly only in tests.
- Back/dispose, TV backgrounding and expiry close the server and discard pending
  credentials. Phone backgrounding closes its client. If the phone leaves after
  sending, explicitly reject on the TV or wait for expiry to cancel there too.
- After approval the TV briefly waits for a phone status poll, then uses the
  existing bounded login flow. Phone acknowledgement means **TV accepted**, not
  **provider authenticated**. Lost acknowledgements are reported conservatively.
- Dart strings cannot be reliably zeroized; discard references promptly, never
  log account/QR secrets, and use existing secure storage only after login.
- Local pairing encryption does not upgrade an HTTP provider connection to HTTPS.

## Platform notes and references

- `mobile_scanner` 7.1.4 is pinned: bundled Android ML Kit avoids an initial Google
  Play Services model download (important for Fire TV / offline scanning).
  Its Darwin podspec supports iOS 12 / macOS 10.14, below our existing targets.
  Camera permission is optional and only requested on the phone scanner screen.
  Android camera/autofocus features are explicitly optional to retain TV support.
- iOS declares camera and local-network purpose strings; no photo-library access
  or Bonjour browser permissions are requested.
- Target SDK remains 36. [Android local-network permission documentation](https://developer.android.com/privacy-and-security/local-network-permission)
  explicitly says not to request ACCESS_LOCAL_NETWORK for SDK 36 or lower.
  Implement its runtime permission before migrating to target SDK 37.
- [Scanner lifecycle guidance](https://pub.dev/packages/mobile_scanner/versions/7.1.4)
  is handled by the scanner widget's owned controller (no custom controller).
- [AES-GCM API](https://pub.dev/documentation/cryptography/latest/cryptography/AesGcm-class.html).

## Validation / release gate

Implementation validation (September 30, 2026): all 277 Flutter tests passed.
Analyzer reports no errors/warnings and the same 21 pre-existing informational
findings. Android debug APK, macOS debug app, and unsigned iOS simulator builds
passed with local Flutter 3.47.4. Its automatic Apple project migrations were
removed afterward; the existing iOS 13 / macOS 10.15 targets and CocoaPods
configuration remain. Recheck native builds with CI's pinned Flutter 3.38.9
before release; these local builds do not validate older OS runtime support.

Automated protocol tests cover encrypted loopback exchange, explicit approval,
matching codes, rejection, multiple senders, idempotency, expiry, cancellation,
M3U handling, malformed/public QR endpoints, wrong keys, tampered/reflected
ciphertext, response replay, oversized payloads and browser-origin rejection.
Widget tests cover a small phone with enlarged text, manual recovery, TV focus,
and background cancellation. Existing login and profile tests remain in scope.

Before shipping, test with a real phone and TV: Android + iPhone camera allow/deny,
iOS local-network allow/deny, TV Ethernet + phone Wi-Fi, expired/reused QR,
guest Wi-Fi, VPN, multiple interfaces, back/home/sleep during transfer, provider
login failure and saved/M3U accounts. Automated loopback tests do not prove
physical-device camera or LAN compatibility.

The in-repo privacy policy and in-app privacy explanation describe pairing.
Deploy the public privacy page and review Play/App Store privacy declarations
before releasing. No store submission or release is performed by this feature.
