# Native distributie

Gebruik Flutter 3.50.0 en het vastgelegde pubspec.lock. De GitHub-workflow levert testbare artifacts, zonder appstorepublicatie.

## Android

`flutter build apk --debug` levert de installeerbare test-APK. Debugkeys op CI zijn geen blijvende release-identiteit; een volgende CI-build kan een andere sleutel hebben. Maak voor publieke releases een eigen keystore, bewaar deze veilig buiten Git, configureer `signingConfigs.release` via CI-secrets en bouw `flutter build appbundle --release` voor Google Play. De gegenereerde releaseconfig gebruikt nu de Flutter-debugkey en mag niet als publieke release worden beschouwd.

## Windows

`flutter build windows --release`. De volledige Release-map moet meegeleverd worden, inclusief DLL’s en data. CMake neemt de Visual C++-runtime uit de compilerinstallatie mee; CI controleert dat deze aanwezig is. Inno Setup maakt met `packaging/windows/installer.iss` een installer per gebruiker, zonder administratorrechten. De installer verwijdert bij deïnstallatie geen zelfgekozen studieboekmappen. Codesigning voor publieke distributie is een afzonderlijke stap.

## macOS

`flutter build macos --release`. De workflow verpakt de app in een DMG. Voor een gewone publieke download moet de app met een Developer ID worden ondertekend en genotariseerd. De sandbox-entitlements voor maptoegang en bookmarks moeten bij ondertekening behouden blijven.

## iOS

Bouw op macOS met Xcode. `flutter build ios --release --no-codesign` controleert de compilatie, maar levert geen op een iPhone installeerbare release. Stel een eigen Bundle ID, Apple-team, signingcertificaten en provisioning in. Bouw vervolgens een ondertekend archief/IPA en gebruik TestFlight voordat je de App Store-release indient.

## Linux

`flutter build linux --release`. De portable tar bevat het gehele Flutter-bundle. `bash packaging/linux/package-deb.sh` maakt een Debian/Ubuntu-pakket. CI bouwt op Ubuntu 22.04 x64 (glibc 2.35); de binaries vragen een compatibele of nieuwere distributie met GTK 3. Test ook op de specifieke distributies die je officieel wilt ondersteunen.

## Controle vóór een publieke release

Op ieder doelplatform: nieuw studieboek maken via systeemkiezer; notitie opslaan; app volledig afsluiten; opnieuw openen; bestaande map openen; annuleren; locatie verplaatsen/verwijderen; toegang intrekken; opslagfout simuleren. Controleer ook langere notities, toetsenbord, schermlezer en grotere tekst. Test Android/iOS met lokale opslag én de specifieke cloudprovider die je wilt ondersteunen. Ondersteuning van een systeemkiezer betekent niet dat iedere provider dezelfde bestandssemantiek heeft.

## PWA en Dropbox

De workflow bouwt ook een statische PWA als `Mosterdzaad-web`. Zie [PWA](PWA.md) voor hosting en offline-updates, en [Dropbox](DROPBOX.md) voor de appregistratie, redirectadressen en controle met echte accounts. De native builds gebruiken dezelfde Dropbox-app key.
