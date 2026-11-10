# DirectSwitch Wire Protocol Specification — v1.1

**Proprietà e Copyright:** © 2026 Nicolas Donati. Tutti i diritti riservati.

Questo documento definisce il contratto formale di rete, auto-discovery e crittografia tra **DirectSwitch-Android** (`com.directswitch.android`, v1.1.0) e **DirectSwitch-iOS** (`com.directswitch.ios`, v1.1.0) per il trasferimento diretto a telefoni già configurati.

---

## 1. Regola Licenza di Sessione ("Intra-OS Free + Single-Side Cross-OS Pro")

Ogni sessione accoppia una **Sorgente (`senderPlatform`)** e una **Destinazione (`receiverPlatform`)**:
- **Intra-OS (`ANDROID → ANDROID` oppure `IOS → IOS`)**: livello `INTRA_OS_FREE` — **100% sbloccato gratuitamente** per tutte le categorie supportate (Contatti, Foto/Video 4K, Album, Calendari, Documenti, WhatsApp Vault, SMS di sistema su Android).
- **Cross-OS (`ANDROID → IOS` oppure `IOS → ANDROID`)**:
  - Se **almeno uno** dei due dispositivi presenta `hasPro == true` (verificato tramite Google Play Billing v7 o Apple StoreKit 2) oppure `hasCloudSavePro == true` dentro l'handshake cifrato → livello `CROSS_OS_PRO_UNLOCKED` (**Single-Side Unlock**: l'utente paga su un solo Store e sblocca entrambi i telefoni).
  - Se nessuno dei due ha ancora sbloccato il Pass → livello `CROSS_OS_PREVIEW` (connessione reale, scansione completa GB, **Rubrica Contatti completa gratuita** + anteprima primi 25 media; Calendari, SMS, Documenti/WhatsApp Vault e libreria media completa richiedono il Pass Pro).

---

## 2. QR Code Pairing (`DSWITCH_V1`) & Secret-Free UDP Beacon (`DSWITCH_BEACON_V1`)

### 2.1 Payload QR Completo (`DSWITCH_V1`)
Il dispositivo **Ricevente** avvia il listener TCP locale sulla porta `49443` (e opzionalmente `LocalOnlyHotspot` 5GHz su Android) codificando **esclusivamente nel QR Code** (o nello scambio PIN cifrato) la chiave di sessione a 256 bit:

```json
{
  "proto": "DSWITCH_V1",
  "sessionId": "ds_8f42b1c9e0a34712",
  "receiverName": "iPhone 16 Pro",
  "receiverPlatform": "IOS",
  "ips": ["192.168.1.44", "192.168.43.1"],
  "port": 49443,
  "sessionKeyHex": "64-hex-chars-256bit-key",
  "wifiSsid": "AndroidShare_5821",
  "wifiPass": "k9P4mQ2x8Z",
  "receiverHasPro": false
}
```

### 2.2 Beacon UDP Auto-Discovery Senza Segreti (`DSWITCH_BEACON_V1`)
Sulla porta UDP `49444`, sia Android sia iOS trasmettono **unicamente** il beacon pubblico privo di `sessionKeyHex` e `wifiPass`:

```json
{
  "proto": "DSWITCH_BEACON_V1",
  "sessionId": "ds_8f42b1c9e0a34712",
  "receiverName": "iPhone 16 Pro",
  "receiverPlatform": "IOS",
  "ips": ["192.168.1.44"],
  "port": 49443,
  "receiverHasPro": false
}
```

Quando l'utente seleziona il dispositivo rilevato automaticamente senza usare la fotocamera, inserisce il **PIN monouso a 6 cifre** mostrato sul telefono ricevente. Da `(sessionId, pin)` viene derivata una chiave simmetrica tramite `HKDF-SHA256` seguita da **60.000 iterazioni di `HMAC-SHA256`** per autenticare `POST /v1/pair-pin` (bloccato dopo 3 tentativi errati).

---

## 3. Cifratura Streaming `CSGCM1` (100% Compatibile Android ↔ Apple CryptoKit)

Dalla `sessionKeyHex` (32 byte) si deriva la chiave operativa tramite `HKDF-SHA256(salt = "DirectSwitch-Salt-2026", info = "DirectSwitch-CSGCM1-v1")` (RFC 5869).
- Magic Header `6 byte` ASCII: `"CSGCM1"`
- Sequenza di **almeno 1 blocco autenticato** (anche per file da `0 byte`, impedendo la falsificazione di stream vuoti non autenticati) da max `4.194.304 byte` (`4 MiB`) di plaintext ciascuno:
  `[4B Big-Endian blockPayloadLen][12B Nonce][Ciphertext][16B GCM Tag]`

---

## 4. Endpoint HTTP/1.1 Locali Autenticati sul Ricevente

Accettati solo da indirizzi IPv4 RFC1918 / link-local (`10/8`, `172.16/12`, `192.168/16`, `169.254/16`):

1. **`GET /v1/ping`** → Verifica raggiungibilità IP candidato.
2. **`POST /v1/pair-pin`** *(busta `CSGCM1` con chiave derivata dal PIN a 6 cifre)* → Scambio monouso del `QrPairingPayload` (max 3 tentativi).
3. **`POST /v1/handshake`** *(busta `CSGCM1`)* → Verifica `sessionId`, scambia modello, OS, spazio libero reale (`freeStorageBytes`), stato Pass Pro e restituisce `SessionLicenseTier` + `hasEnoughSpace`.
4. **`POST /v1/manifest`** *(busta `CSGCM1`)* → Invia `TransferManifest` (contatti con normalizzazione E.164, foto/video con data EXIF + dimensione + album, calendari deduplicati, SMS, documenti e WhatsApp Vault). Il Ricevente esegue **Smart Merge & Anti-Duplicati** e restituisce `acceptedItemIds`.
5. **`PUT /v1/item/{itemId}`** *(stream `CSGCM1` su disco)* → Stream binario cifrato a blocchi da 4 MiB con header `X-DS-Plain-Length` e `X-DS-Sha256` verificati end-to-end prima del salvataggio su `MediaStore` / `PhotoKit` / `Download/DirectSwitch` / `File` di iOS.
6. **`POST /v1/complete`** *(busta `CSGCM1`)* → Finalizza il report certificato `TransferCompletionReport`.
7. **Portale Bootstrap Guidato (`/start?token=...`, `/download/directswitch.apk?token=...`, `/download/contacts.vcf?token=...`)** → Disabilitato per default; attivo su Android solo quando l'utente avvia esplicitamente il Portale QR sul vecchio telefono e protetto in tempo costante da un token casuale a 128 bit.
