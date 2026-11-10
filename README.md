# DirectSwitch (v1.1.0)

**Copyright © 2026 Nicolas Donati. Tutti i diritti riservati.**

App nativa cross-platform di trasferimento diretto telefono-a-telefono **a dispositivi già configurati** (senza formattazione, senza cloud, con crittografia streaming `CSGCM1` AES-256-GCM e Smart Merge zero duplicati), affiancata al ponte rapido verso **Configura / Android Switch** nativo di Google quando applicabile.

## Modello Prodotto
- **Intra-OS Gratuito al 100%**: `Android ↔ Android` e `iPhone ↔ iPhone` completi e illimitati.
- **Ponte Cross-OS Pro (`Android ↔ iPhone`)**: sblocco *Una Tantum* verificato crittograficamente (Google Play Billing v7 / Apple StoreKit 2) su **un solo telefono** (*Single-Side Unlock*), valido per entrambi i dispositivi della sessione, oppure sbloccato con abbonamento **CloudSave Pro** verificato.

## Struttura del Progetto
- `DirectSwitch-Android/`: App nativa Kotlin + Jetpack Compose (`com.directswitch.android`, `minSdk 26`, `targetSdk 36`, R8 + Resource Shrinking attivi):
  - Trasporto locale cifrato `CSGCM1` + Hotspot 5GHz offline (`LocalOnlyHotspot`) + Auto-Discovery UDP protetta da PIN monouso a 6 cifre.
  - Smart Merge Contatti, Foto/Video 4K con EXIF/GPS, Calendari deduplicati, Documenti & WhatsApp Vault compatibili Scoped Storage Android 11–16 (MediaStore + SAF picker + Share Sheet `Condividi con DirectSwitch` e salvataggio in `Download/DirectSwitch/`).
  - Migrazione SMS di sistema con persistenza messaggi reali in arrivo durante `ROLE_SMS` e ripristino guidato dell'app Messaggi predefinita.
- `DirectSwitch-iOS/`: App nativa Swift 5.9 + SwiftUI (`com.directswitch.ios`, iOS 16+):
  - Server/Client `Network.framework` (`NWListener`) con streaming su disco a blocchi da 4 MiB anti-OOM per video 4K multi-GB e ripresa idempotente (`completedItemIds`).
  - Aggancio automatico Hotspot 5GHz (`NEHotspotConfigurationManager`) con fallback guidato e copia automatica password negli appunti per installazioni su Apple ID gratuito (`Free-Install.ipa`).
  - Auto-Discovery UDP bidirezionale con PIN a 6 cifre, Portale QR Rapido Rubrica `.vcf` protetto da token a 128 bit, `CNContactStore`, `PhotoKit` (con preservazione Album utente reali e MIME HEIC/MOV/MP4), `EventKit` (iOS 17+ Full Access), Dashboard spazio/contenuti e ricezione diretta `Apri in DirectSwitch` da WhatsApp (`Esporta chat`) e dall'app `File`.
- `docs/DIRECTSWITCH_PROTOCOL_V1.md`: Specifica formale del protocollo `DSWITCH_V1` / `DSWITCH_BEACON_V1` / `CSGCM1`.
- `INSTALLA_DIRECTSWITCH_ANDROID.bat`: Installazione rapida via USB del pacchetto release firmato `DirectSwitch-Android-Install.apk`.
- `INSTALLA_DIRECTSWITCH_SU_IPHONE.bat`: Avvio guidato di Sideloadly per installare `DirectSwitch-Free-Install.ipa` su iPhone via USB con Apple ID gratuito.

## Build Release Android (Windows / Linux / macOS)
Copia o crea `DirectSwitch-Android/keystore.properties` (ignorato da Git) oppure esporta le variabili d'ambiente `DS_STORE_FILE`, `DS_STORE_PASSWORD`, `DS_KEY_ALIAS`, `DS_KEY_PASSWORD`, quindi esegui:
```powershell
cd DirectSwitch-Android
.\gradlew.bat testDebugUnitTest assembleRelease
```

## Build IPA iOS (`Free-Install.ipa` + `Release.ipa` su macOS / GitHub Actions)
Il workflow `.github/workflows/directswitch-ci-release.yml` compila su runner `macos-15` (tramite `XcodeGen` + `xcodebuild`), esegue la suite `DirectSwitchTests` su simulatore iOS e genera automaticamente:
1. **`DirectSwitch-Free-Install.ipa`**: privo di entitlement ristretti a pagamento, installabile immediatamente da Windows via Sideloadly con qualsiasi Apple ID gratuito.
2. **`DirectSwitch-Release.ipa`**: firmato con `DirectSwitch.entitlements` (`HotspotConfiguration` + `App Groups`) per account Apple Developer Program / App Store Connect.
