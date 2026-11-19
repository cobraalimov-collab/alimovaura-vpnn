# NodeShield — Flutter WireGuard VPN client (Android)

> **Status:** written carefully but **not compiled here** (no Flutter SDK / network in the
> authoring environment). Expect to fix small API drift in `lib/vpn_engine.dart` if your
> `wireguard_flutter` version differs. Test on a **physical Android device**.

## 1. Create the project and drop the files in

```bash
flutter doctor                       # all Android items must be green
flutter create --org com.nodeshield --project-name nodeshield_vpn --platforms android nodeshield_vpn
cd nodeshield_vpn
```

Copy from this bundle, overwriting what `flutter create` generated:

| From this bundle | To |
|---|---|
| `pubspec.yaml` | project root |
| `lib/*.dart` | `lib/` (delete the sample `lib/main.dart` first) |
| `android/app/src/main/AndroidManifest.xml` | same path |
| `android/app/src/main/kotlin/com/nodeshield/nodeshield_vpn/MainActivity.kt` | same path (delete any other `MainActivity.kt`) |
| `android/app/proguard-rules.pro` | `android/app/` |

```bash
flutter pub get
```

## 2. Gradle settings (`android/app/build.gradle.kts`)

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "com.nodeshield.nodeshield_vpn"
    defaultConfig {
        applicationId = "com.nodeshield.nodeshield_vpn"   // permanent once published!
        minSdk = 23                                        // wireguard needs >= 21
        targetSdk = 35   // use the level Play Console currently requires (check Play Console → Policy)
    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
```

If the Flutter version you have still generates Groovy (`build.gradle`), translate the same values.

## 3. Create a signing key (once — back it up, you can't recover it)

```bash
keytool -genkey -v -keystore ~/nodeshield-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties` (**never commit it**):

```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/home/you/nodeshield-upload.jks
```

## 4. Run & test

1. Open `lib/config.dart`. With `kUseMockBackend = true` the app needs no backend. Paste a real
   client `.conf` from your own WireGuard server into `kDevWgConf`.
2. `flutter run` on a physical device. Tap the power button → accept Android's **VPN
   connection request** dialog → the tunnel comes up and the key icon appears in the status bar.

## 5. Build for the Play Store

```bash
flutter build appbundle --release                    # → build/app/outputs/bundle/release/app-release.aab  (upload this)
flutter build apk --release --split-per-abi          # → per-ABI APKs for sideloading/testing
```

Bump `version: 1.0.0+N` in `pubspec.yaml` for every upload.

## 6. Google Play requirements for VPN apps (don't skip)

- Fill in Play Console → **App content → VPN service declaration**. VPN apps must use
  `VpnService` only for a core VPN function and encrypt traffic.
- Publish a **privacy policy** URL, complete the **Data safety** form, and make sure any
  "no logs" claim is literally true of your backend.
- Don't collect/sell traffic data, and don't inject ads/redirect traffic via the VPN.
- Create the app, run **closed testing** (new personal accounts need a testing period before production).

## 7. Backend API contract (what `lib/api_service.dart` expects)

Base URL = `kApiBaseUrl`. Set `kUseMockBackend = false` when ready. JSON errors may include `{"message": "..."}`.

| Call | Request | Response |
|---|---|---|
| `POST /auth/email/request` | `{"email": "a@b.com"}` | `200` (emails a 6-digit code) |
| `POST /auth/email/verify` | `{"email","code"}` | `{"token": "<jwt>"}` |
| `GET /servers` (Bearer) | – | `[{"id":"de-fra","country":"Germany","city":"Frankfurt","flag":"🇩🇪","ping_ms":24}]` |
| `POST /wireguard/peer` (Bearer) | `{"server_id","public_key"}` | `{"address":"10.8.0.2/32","dns":["1.1.1.1"],"server_public_key":"...","endpoint":"1.2.3.4:51820","allowed_ips":["0.0.0.0/0","::/0"],"preshared_key":"...?","mtu":1420?}` |

The server must add `public_key` as a peer with the assigned `address` (e.g. `wg set wg0 peer <pub> allowed-ips 10.8.0.2/32`).
The **private key is generated on the phone** and never leaves it.

## 8. Project layout

```
lib/main.dart          UI: power button, timer, server sheet, stats, email sign-in sheet
lib/providers.dart     Riverpod state: auth, servers, VPN controller (connect/disconnect/speeds/timer)
lib/vpn_engine.dart    wireguard_flutter wrapper: init, connect, disconnect, state stream + traffic counters
lib/wg_config.dart     .conf parser/validator/serializer
lib/api_service.dart   backend client + on-device X25519 key generation
lib/models.dart  lib/config.dart
android/.../MainActivity.kt   TrafficStats channel for live speed
```

## 9. Troubleshooting

- **`startVpn` signature / enum errors** → open the plugin's README for your version and adjust only `vpn_engine.dart`.
- **Stuck on "Connecting"** → wrong endpoint/keys, UDP 51820 blocked, or server lacks your peer. Check `adb logcat | grep -i wireguard`.
- **Speed shows 0.00** → traffic counters need a moment; generate traffic (open a web page). Values are the app UID's tunnel bytes (≈ VPN throughput + overhead).
- **R8 crash in release only** → confirm `proguard-rules.pro` is referenced and keep rules are intact.
- Wallet login is a UI placeholder; integrate WalletConnect/Reown AppKit if you need it.
