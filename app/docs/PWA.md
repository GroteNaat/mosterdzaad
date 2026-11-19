# PWA bouwen en aanbieden

De PWA gebruikt dezelfde Flutter-interface en hetzelfde studieboekformaat als de
native apps. Notities staan in **IndexedDB per browser/origin**; de zoekindex is
een opnieuw op te bouwen geheugenindex. Er is geen eigen serverdatabase nodig.
De browser kiest geen lokale map: iOS geeft geen blijvende toegang tot een
zelfgekozen map in Bestanden. Via Dropbox of een reservekopie kun je van apparaat wisselen.

## Bouwen

Met Flutter 3.50.0, vanuit `app/`:

```sh
flutter pub get --enforce-lockfile
flutter build web --release --no-web-resources-cdn
dart --disable-dart-dev tool/prepare_pwa.dart
```

Voor een subpad, bijvoorbeeld `/mosterdzaad/`:

```sh
flutter build web --release --no-web-resources-cdn --base-href /mosterdzaad/
dart --disable-dart-dev tool/prepare_pwa.dart
```

Gebruik de **volledige inhoud** van `build/web/` op een statische HTTPS-host.
GitHub Actions levert die map als `Mosterdzaad-pwa.zip` in het artifact
`Mosterdzaad-web`. De workflow publiceert niets. `flutter build web` alleen maakt
nog geen offline app: de tweede opdracht genereert de service worker met de exacte
assetlijst en versiehash. CanvasKit, lettertypes en bijbelmetadata worden meegeleverd.

Houd het webadres en het subpad stabiel. Bij verhuizen naar een andere origin is
de oude browserdatabase niet automatisch beschikbaar. Maak eerst een reservekopie
of synchroniseer en open op het nieuwe adres vanuit Dropbox.

## Hosting

- HTTPS is nodig voor installatie en de service worker. `http://localhost` werkt
  voor lokaal testen. Dien `.wasm` als `application/wasm` en JS als JavaScript op.
- `index.html`, `flutter_bootstrap.js`, `service_worker.js` en `auth.html`:
  `Cache-Control: no-cache` (voor `auth.html` bij voorkeur `no-store`).
  Cache HTML nooit langdurig op een CDN.
- `auth.html` moet echt het callbackbestand zijn; stuur dit niet naar een SPA
  fallback. Registreer het exacte adres in de Dropbox-console (zie [Dropbox](DROPBOX.md)).
- Geen COOP `same-origin` instellen: dat kan het OAuth-openerkanaal verbreken.
  Deze build heeft geen COOP/COEP-headers nodig.
- Bij een CSP moeten de vereiste Flutter/CanvasKit-scripts en WebAssembly toegestaan
  zijn en `connect-src` de Dropbox API-hosts toelaten. Voeg geen analytics of scripts
  van derden toe die de lokale notities kunnen lezen.

## Installeren, offline gebruik en updates

Open de app eerst met internet. Wacht op **Mosterdzaad is klaar voor offline gebruik**.
Op iPhone/iPad: Safari → Deel → Zet op beginscherm. Op Android/desktop gebruik je de
installatieoptie van de browser. Er is geen App Store-account vereist voor de PWA.

De service worker cachet alleen de gebouwde appassets. Dropbox-verkeer, OAuth-
callbacks en notities komen nooit in die cache. Een nieuwe versie wacht tot alle
appvensters gesloten zijn; de app toont hiervoor een melding. Er is geen geforceerde
reload die een open concept kan weggooien. Alleen eigen oude assetcaches worden
verwijderd. IndexedDB blijft bij een appupdate intact.

De browser wordt gevraagd om persistente opslag, maar kan dit weigeren. Het wissen
van websitegegevens, een privévenster, opslagdruk of verwijderen van de PWA kan
gegevens laten verdwijnen. Onder **Instellingen → Reservekopie downloaden** exporteer
je het volledige studieboek, inclusief geschiedenis. **Reservekopie herstellen**
op het startscherm maakt hiervan een nieuwe lokale kopie. Dit betreft Flutter-
studieboeken, geen imports uit de oude Django-app.

## Testen

```sh
flutter test
npm install --no-save --prefix build/pwa-test-runner playwright@1.62.1
# Gebruik een geïnstalleerde Chromium-browser via CHROME_EXECUTABLE,
# of installeer een testbrowser met Playwright.
PLAYWRIGHT_MODULE="$PWD/build/pwa-test-runner/node_modules/playwright" node tool/test_pwa.cjs
```

De opslageenheidstests controleren exclusief schrijven en de catalogus met een
IndexedDB-testadapter. De Playwright-test draait de echte releasebuild en controleert
notities bewaren, herladen zonder internet en reservekopieën exporteren/herstellen. Controleer daarnaast de releasebuild met een
statische server: maken, bewaren, herladen, offline herladen, export/herstel,
Dropbox aanmelden, tweede apparaat en een appupdate met open concept. Doe de
laatste controle ook op een echte iPhone/iPad; een Chromium-test bewijst geen
Safari- of beginschermcompatibiliteit.

## Versleutelde synchronisatie

De offline build bevat ook Loro-WASM, libsodium-sumo, de Argon2-Web Worker en de browserkluis. Laat bij een CSP lokale workers en WebAssembly toe; Dropbox gebruikt ook notify.dropboxapi.com voor longpoll. De gegevenssleutel en refresh token worden verpakt met een niet-exporteerbare WebCrypto-key in IndexedDB. Dit is geen OS-keychain en biedt geen bescherming tegen XSS of een kwaadaardige appupdate. Gebruik een eigen HTTPS-origin en geen scripts van derden.

`node tool/test_sync_browser.cjs` voert de gedeelde cryptografie-/synchronisatieproeven en een browserkluis-herstarttest uit. Zie [protocol en beperkingen](ENCRYPTED-SYNC.md).
