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

Maak/open een lokaal studieboek. Kies **Instellingen → Dit studieboek koppelen**
en meld je aan bij Dropbox in de systeembrowser. De eerste synchronisatie plaatst
een kopie in de eigen appmap in Dropbox. Op een tweede apparaat kies je
**Uit Dropbox openen** en het gewenste studieboek. Native apps vragen vervolgens
waar de lokale kopie moet komen; de PWA bewaart die in de browser.

Je kunt offline notities opslaan. Bij een actieve koppeling synchroniseert de app
na opslaan (met een korte vertraging), bij hervatten, eenmaal per minuut terwijl
de app open is, en via **Nu synchroniseren**. Controleer de laatste succesvolle
synchronisatie voordat je van apparaat wisselt. Mislukt de verbinding, dan blijven
lokale wijzigingen bewaard en volgt bij een volgende poging een nieuwe samenvoeging.

Aanmelden gebruikt authorization code + PKCE/S256, een willekeurige `state` en
controle van het volledige callbackadres. Kortlevende toegangstokens blijven
alleen in het procesgeheugen. **Na volledig sluiten/herladen of verlopen van de
sessie is opnieuw aanmelden nodig.** De koppeling wordt pas actief wanneer je
het boek koppelt of vanuit Dropbox opent. Er zijn geen refresh tokens en geen
achtergrondsynchronisatie wanneer de app gesloten is. Verbinding verbreken stopt
de koppeling in deze sessie en verwijdert geen lokale of cloudgegevens. Toegang
voor de app volledig intrekken kan in de instellingen van je Dropbox-account.

## Formaat, conflicten en grenzen

- Per studieboek: `/<studieboek-uuid>.mosterdzaad.json` in de Dropbox-appmap.
  Het bestand bevat het originele manifest en alle Markdown/JSON-revisies.
  De native SQLite-index, maprechten en authenticatiegegevens ontbreken bewust.
- Een cloudbestand is maximaal **20 MiB**, inclusief geschiedenis en JSON-encoding.
  Iedere upload verstuurt de volledige kopie. Dit is geschikt voor tekstnotities;
  bij grotere verzamelingen zijn een incrementeel protocol en bestandbijlagen
  vervolgwerk. Overschrijden geeft een melding en laat de lokale gegevens staan.
- Dropbox `rev` plus `mode:update`/`strict_conflict` beschermt tegen gelijktijdige
  overschrijving. Bij een race wordt opnieuw opgehaald, samengevoegd en geprobeerd.
  De volledige cloudkopie wordt atomair gepubliceerd.
- Samenvoegen is de vereniging van de revisiegeschiedenissen. Ontbrekende
  bestanden betekenen geen verwijdering; verwijderen in de app schrijft een
  nieuwe revisie. Gelijktijdige wijzigingen blijven als beide versies zichtbaar
  bij **Instellingen → Herstel en geschiedenis**, ook een bewerking versus verwijdering.
- Ontvangen kopieën worden volledig gecontroleerd vóór lokaal schrijven. Ouders
  worden vóór hun opvolgers geschreven. Een gewijzigd bestand met dezelfde
  revisie-ID, onvolledige geschiedenis of onverenigbare versindeling stopt de sync.
  Bestanden handmatig aanpassen is daarom niet geschikt voor gekoppelde boeken.
- De inhoud is leesbaar in de Dropbox-account; er is geen extra end-to-end-encryptie.
  Dropbox-sync vervangt geen afzonderlijke reservekopie.

## Valideren met echte accounts

De geautomatiseerde tests gebruiken een Dropbox-API-testdouble voor offline
wijzigingen, races, fouten, conflicten en PKCE. Test de echte aanmeldflow en
overdracht na het registreren van de redirectadressen: twee apparaten, offline
wijzigingen op beide, herverbinden, conflict oplossen, verlopen sessie en toegang
intrekken. Test vooral Safari én een op het beginscherm geïnstalleerde iOS-PWA:
Safari kan de callback in een apart browservenster openen. De callbackpagina
ondersteunt zowel `postMessage` als een tijdelijke callback in lokale browseropslag;
de PKCE-verifier en toegangstokens worden daar nooit opgeslagen.

De auth-plugin is vastgezet op 6.0.0-alpha.11 wegens de gebruikte Flutter/AGP 9
toolchain. De gedocumenteerde desktop-webview opt-out staat in `packages/`;
Windows/Linux gebruiken altijd de systeembrowser en vragen geen WebKit/WebView2.
