# Mosterdzaad

Een lokale Bijbelstudie-app voor Android, iOS, Windows, macOS en Linux, met een installeerbare PWA voor de browser. Offline gebruiken kan zonder account of eigen server. Optionele Dropbox-synchronisatie gebruikt je eigen Dropbox-account.

De Flutter-app staat in [`app/`](app/). Deze ontwikkelbranch bevat de Flutter-opvolger van de oorspronkelijke Django-webapp. De oude broncode is nog aanwezig als referentie; de oorspronkelijke installatiehandleiding staat in [docs/SELF-HOSTED.md](docs/SELF-HOSTED.md).

## Beginnen

Bij de eerste start kies je **Nieuw studieboek maken** of **Studieboek openen**. De app gebruikt de systeemdialoog om een map te kiezen. Een nieuw studieboek krijgt een eigen submap in de gekozen locatie. Bestaande studieboeken open je door de map met `mosterdzaad.json` te selecteren.

De app onthoudt de locatie en opent het studieboek bij een volgende start opnieuw. Bij een verplaatste map, ingetrokken toestemming of ontbrekende schijf kun je opnieuw kiezen. Annuleren maakt geen leeg vervangend studieboek.

Op iPhone/iPad is de eigen documentmap zichtbaar in Bestanden. Studieboeken binnen die appmap worden bij het verwijderen van de app ook verwijderd; kopieer ze vooraf naar een andere locatie of kies een map in iCloud Drive.

- Notities met meerdere passages, thema’s, leesplannen en studies.
- Bijbeltracker met hoofdstuk- en versoverzichten; overlap telt één keer.
- Leesplannen met 1–366 bewerkbare sessies en overdenkingen.
- Bijbelstudies met datum en persoonlijke groepslabels.
- Zoeken op tekst, verwijzingen en gekoppelde onderdelen.
- Eerdere versies, prullenbak en expliciete afhandeling van gelijktijdige wijzigingen.
- Nederlandse interface die zich aanpast aan telefoon en desktop.

Er worden geen Bijbelteksten meegeleverd. De hoofdstuk- en versmetadata zijn dezelfde als in de oorspronkelijke app. Een vers telt mee als er een niet-lege notitie aan gekoppeld is. De versindeling staat vast zodra er passages in de geschiedenis voorkomen.

## Waar staan mijn gegevens?

Alle inhoud en eerdere versies staan in de gekozen studieboekmap. Notities zijn leesbare Markdownbestanden met metadata; andere onderdelen zijn JSON-records. Een SQLite/Drift-zoekindex in de lokale appcache is afgeleid van deze bestanden. Verwijderen van de cache verwijdert geen notities.

Maak regelmatig een kopie van **de volledige studieboekmap**. In de PWA staan de records in IndexedDB en kun je een reservekopie downloaden en herstellen. Browseropslag blijft afhankelijk van je browser en kan worden gewist.

Bij **Instellingen → Dit studieboek koppelen** activeer je Dropbox-synchronisatie. Open op een tweede apparaat met **Uit Dropbox openen**. De volledige geschiedenis wordt samengevoegd; concurrente versies blijven behouden. Aanmelden geldt voor de appsessie, synchronisatie werkt terwijl de app open is. Zie [Dropbox instellen en gebruiken](app/docs/DROPBOX.md). Gebruik de ingebouwde sync bij voorkeur met een gewone lokale map, niet tegelijk met een tweede synchronisatieprogramma op dezelfde map.

De bestanden zijn niet versleuteld. Er zijn geen analytics of externe fonts. Alleen bij de vrijwillige Dropbox-koppeling communiceert de app met Dropbox; notities gaan niet naar een Mosterdzaad-server. Zie [opslagformaat en herstel](app/docs/STORAGE.md).

Er is bewust geen import van JSON-exports of databases uit de oude Django-app. **Bestaand studieboek openen** betekent een studieboek van deze Flutter-app.

## Bouwen en testen

Flutter **3.50.0** (Dart 3.14). Gebruik de bijbehorende native ontwikkeltools voor je platform.

```sh
cd app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d windows
```

Gebruik voor een ander apparaat `flutter devices` en `flutter run -d <apparaat>`. Voor iOS en macOS is macOS/Xcode nodig; Windows wordt op Windows en Linux op Linux gebouwd.

[Apps and PWA](.github/workflows/flutter.yml) bouwt op pushes naar deze branch Android, Windows, macOS, iOS, Linux en de PWA. De workflow test ook domeinregels, bestandopslag, conflicten, indexering en widgets. Download de artifacts vanuit de geslaagde GitHub Actions-run:

| Artifact | Inhoud |
|---|---|
| Android | Installeerbare **test-APK**, met debug-ondertekening |
| Windows | Portable ZIP en `.exe`-installer voor x64 |
| macOS | `.dmg`; nog niet ondertekend of genotariseerd voor publieke distributie |
| iOS | **Niet ondertekende build** voor buildcontrole; niet direct installeerbaar |
| Linux | `.deb` en portable `.tar.gz` voor x64 |
| Web | `Mosterdzaad-pwa.zip` voor statische HTTPS-hosting, met offline assets |

Voor publieke Android-releases is een blijvende eigen signing key nodig. Voor TestFlight/App Store zijn Apple-ondertekening, provisioning en een ontwikkelaarsaccount nodig. Zie [distributie](app/docs/RELEASING.md). Er wordt vanuit deze branch niets automatisch in appstores gepubliceerd.

De native mapkoppelingen voor Android en Apple zijn platformcode en moeten naast CI-builds ook op echte apparaten worden beproefd: een map openen, notitie bewaren, de app afsluiten, herstarten en toegang intrekken. Een geslaagde build vervangt die controle niet.

## PWA en Dropbox voorbereiden

De publieke Dropbox-app key is ingesteld. Voor echt aanmelden moeten App folder-toegang, drie scopes en de exacte redirectadressen in de Dropbox App Console kloppen. Er is geen app secret nodig. Zie [Dropbox-configuratie](app/docs/DROPBOX.md).

De PWA-build bevat een manifest, iconen en een service worker. De workflow levert een ZIP en publiceert geen website. Zie [PWA bouwen, hosten en installeren](app/docs/PWA.md) voor HTTPS-hosting, subpaden, iOS-installatie en reservekopieën.

## Licenties

Applicatiecode: [MIT](LICENSE), copyright NathanH. Bijbelmetadata: **CC BY-SA 4.0**, met bronvermelding in [DATA-SOURCES.md](app/assets/data/DATA-SOURCES.md). Roboto: [Apache 2.0](app/assets/fonts/roboto_license.txt). De app toont de afhankelijkheidslicenties onder Instellingen.
