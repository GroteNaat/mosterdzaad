# Dropbox instellen en gebruiken

Mosterdzaad praat rechtstreeks met Dropbox. Er is geen Mosterdzaad-server, geen
Mosterdzaad-account en geen app secret. De publieke app key `01vxprgsncvmvze` is
ingesteld. Een andere app kan worden gebruikt met
`--dart-define=DROPBOX_APP_KEY=jouw_publieke_key` bij `flutter run` of `flutter build`.
Een expliciet lege key schakelt aanmelden uit.

## Eenmalig in de Dropbox App Console

1. Gebruik een **Scoped access / App folder**-app. De key alleen vertelt de
   client niet of de app als App folder of Full Dropbox is geregistreerd;
   controleer dit in de console. Voor deze app is uitsluitend App folder nodig.
2. Zet onder **Permissions** aan: `files.metadata.read`, `files.content.read`,
   `files.content.write`. Sla de wijziging op. Andere scopes zijn niet nodig.
3. Voeg onder **OAuth 2 → Redirect URIs** de exacte adressen toe:

   - Android, iOS en macOS: `nl.mosterdzaad://dropbox`
   - Windows en Linux: `http://localhost:53682/auth`
   - PWA: `https://jouw-domein/jouw-pad/auth.html` (het pad waar de build staat)
   - Lokaal testen, bijvoorbeeld: `http://localhost:8080/auth.html`

   Een ander protocol, poort, subpad of afsluitende slash is een ander adres.
   De PWA leidt dit af van zijn eigen `<base href>`; er is geen backendcallback.
   De desktopapp luistert alleen op `127.0.0.1`, tijdens het aanmelden.
4. In ontwikkelmodus moeten de beoogde Dropbox-testgebruikers toegang hebben.
   Vraag vóór publieke distributie production access aan bij Dropbox.

Referenties: [OAuth/PKCE](https://developers.dropbox.com/oauth-guide),
[App Console](https://www.dropbox.com/developers/apps),
[flutter_web_auth_2](https://pub.dev/packages/flutter_web_auth_2).

## Gebruik

Kies **Instellingen → Dropbox-synchronisatie en back-up → Dit studieboek koppelen**. Na aanmelden kies je een bestaand versleuteld studieboek of maak je een nieuwe kopie met een eigen versleutelingswachtwoord. Bewaar dit wachtwoord in je wachtwoordmanager: zonder het wachtwoord én zonder een nog ontgrendeld apparaat is herstel onmogelijk.

Op een tweede apparaat kies je **Uit Dropbox openen** en gebruik je hetzelfde versleutelingswachtwoord. De gebruiker kiest bij bestaande lokale inhoud tussen samenvoegen en het oorspronkelijke boek apart bewaren. Native apps vragen een lokale map; de PWA gebruikt IndexedDB.

Wijzigingen worden lokaal opgeslagen en kort daarna afzonderlijk versleuteld verstuurd. De app synchroniseert bij openen van een gekoppeld studieboek, terugkeer naar de app of het venster, en twee seconden na opslaan. Snelle opeenvolgende gebeurtenissen worden gebundeld; een wijziging tijdens een lopende synchronisatie krijgt een vervolgronde. Er is geen periodieke Dropbox-controle of longpoll. Bij een netwerkherstelmelding worden achtergebleven wijzigingen en mislukte synchronisaties opnieuw geprobeerd. De knop Nu synchroniseren blijft beschikbaar. Android en iOS kunnen reeds versleutelde uitgaande wijzigingen in een OS-geplande achtergrondtaak versturen; inkomende wijzigingen worden tijdens actief gebruik of hervatten toegepast. Gesloten-app-levering heeft geen gegarandeerde termijn.

De instellingen tonen de wachtrij, laatste synchronisatie en laatste volledige back-up. Je kunt direct synchroniseren, een volledige back-up maken, een herstelpunt als apart boek openen, het wachtwoord wijzigen en het back-upbeleid instellen. De standaard is 100 wijzigingen of 24 uur, met zeven herstelpunten bij opschonen.

Aanmelden gebruikt PKCE/S256 zonder app secret. Refresh tokens en de gegevenssleutel worden afzonderlijk van de studieboekdata opgeslagen: native in platformbeveiligde opslag, in de PWA verpakt met een niet-exporteerbare WebCrypto-key. Browseropslag is geen OS-keychain en beschermt niet tegen scripts die op dezelfde origin kunnen uitvoeren. Gebruik een eigen HTTPS-origin zonder scripts van derden.

Verbinding verbreken verwijdert de lokale koppeling en het refresh token, niet de notities of cloudkopieën. Toegang volledig intrekken kan via je Dropbox-account. Wachtwoord wijzigen verpakt dezelfde gegevenssleutel opnieuw; reeds ontgrendelde apparaten blijven werken. Oude enveloppen in Dropbox-versiegeschiedenis kunnen nog met het oude wachtwoord worden geopend.

## Protocol, migratie en vrijgave

Zie [ENCRYPTED-SYNC.md](ENCRYPTED-SYNC.md) voor de exacte algoritmen, CRDT-keuze, conflictregels, snapshotcontrole, retentie en rollbackbeperkingen. De volledige back-up inclusief geschiedenis is begrensd tot 20 MiB. Lokale data blijft onversleuteld.

De oude plaintext-snapshotclient is verwijderd. Eerder in Dropbox opgeslagen onversleutelde bestanden en versiegeschiedenis worden niet automatisch gewist en kunnen niet met terugwerkende kracht worden beschermd. Controleer een nieuwe versleutelde back-up op een tweede apparaat voordat je oude kopieën handmatig verwijdert.

Geautomatiseerde tests gebruiken een Dropbox-testdouble. Echte aanmelding, tokenverloop, quota en achtergrondgedrag moeten nog op de doelapparaten worden beproefd. Test vooral Safari én een geïnstalleerde iOS-PWA: de callback kan in een apart browservenster openen. De callbackpagina ondersteunt postMessage en een tijdelijke callback in lokale browseropslag; PKCE-verifier en tokens staan niet in die callbackopslag.

De auth-plugin is gepind op 6.0.0-alpha.11 voor de Flutter/AGP 9-toolchain. Windows/Linux gebruiken de systeembrowser via de gedocumenteerde desktop-webview-opt-out. Een build of testdouble bewijst geen werkende productieconfiguratie in de Dropbox-console.
