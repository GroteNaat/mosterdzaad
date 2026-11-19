# Versleutelde synchronisatie — protocol 2

Implementatie van de technische specificatie v2.0 van 19 november 2026. Dit is ontwikkelcode: de vrijgavecontroles onderaan blijven nodig voordat gevoelige gegevens uitsluitend op deze back-ups vertrouwen.

## Keuze van CRDT

Gekozen: **Loro 1.16.2**, via de gepinde `loro_crdt 0.1.0`-binding. De Rust-core levert tekstsequenties, causale versies, snapshots, updates en samenvoegen. Er is geen eigen tekst-CRDT geschreven. Alle native platforms compileren dezelfde core; web gebruikt de meegeleverde Emscripten-module. De binding is jong en heeft een kleine onderhoudsbasis: pinning, een afgeschermde adapter en native/web-interoperabiliteitstests zijn daarom vrijgavevoorwaarden.

Onderzochte alternatieven:

| Bibliotheek | Beoordeling voor deze app |
|---|---|
| [Loro](https://github.com/loro-dev/loro), [Dart-binding](https://github.com/dspiteself/loro-dart) | Volwassen core, tekst-diffs en rijke tekstmarkeringen, hetzelfde binaire formaat op alle platforms. Jonge binding en extra Rust-toolchain zijn aandachtspunten. |
| [Automerge](https://automerge.org/docs/hello/) | Volwassen core; de beschikbare Dart-package bood geen gelijkwaardige bruikbare Flutter-integratie voor alle zes platforms. |
| [dart_crdt 0.4.0](https://github.com/Salakar/dart_crdt) | Pure Dart en uitgebreide eigen tests. Jongere implementatie; onopgeloste updates moeten extern worden behouden en rijke tekst is beperkt. |
| [yjs_dart](https://github.com/jagtesh/yjs-dart) | Pure Dart-port, maar minder geschikte onderhouds- en interoperabiliteitsbasis voor deze migratie. |

Voor selectie is een werkend browserprototype uitgevoerd: twee gelijktijdig bewerkte alinea’s, emoji’s, dubbele en verkeerd geordende updates, heropenen en opslaan vanuit een verouderd editorvenster. `tool/test_sync_browser.cjs` voert vervolgens de gedeelde protocolcontroles uit. `test/crdt_fixture_test.dart` leest een door WebAssembly geproduceerde fixture; CI stuurt de native update terug naar de browsertest.

## Lokale wijzigingen en samenvoegen

De lokale database en zoekindex blijven **onversleuteld**. Een record bevat een willekeurige operatie-ID, object-ID, causale ouders, apparaat-actor, onveranderlijke aanmaakdatum, tombstone en een Loro-update. De gekozen map of IndexedDB is de bron voor de interface. Een duurzame commitmarker publiceert een volledig teruggelezen record; onafgemaakte pogingen blijven ongepubliceerd en een retry krijgt een nieuwe poging-ID. Zie [opslag](STORAGE.md).

Elke edit krijgt een uit zijn willekeurige operatie-ID afgeleide 64-bits Loro-peer. De apparaat-actor is afzonderlijk persistent. Hierdoor kunnen twee editorvensters vanaf verschillende causale bases opslaan zonder dezelfde peer-teller opnieuw te gebruiken. Bestaande v1-geschiedenis wordt met deterministische actors ingelezen; bestaande bestanden worden niet overschreven. Een oud clientprogramma wordt door een formaatmarker tegen schrijven beschermd.

- `body` en `description`: Loro-tekst. Markdown blijft tekst; er is geen nieuwe WYSIWYG-editor.
- Thema-, plan- en studiekoppelingen: observed-remove-set met unieke toevoegingstags op Loro-maps. Een niet-geobserveerde gelijktijdige toevoeging blijft behouden.
- Titel, overige metadata en leesplansessies: causale Loro-registers met een zichtbare meerwaardigheidsweergave bij concurrerende verschillende waarden. Keuze van metadata behoudt de samengevoegde tekst. Referentietekst en geparste passages vormen één register.
- Volgorde van sessies: de sessielijst is één register; gelijktijdige verschillende ordeningen blijven als alternatieven beschikbaar. Dit is geen rijketekst-CRDT per sessie.
- Verwijderen versus gelijktijdig bewerken: verwijderen wint zichtbaar in de prullenbak, met de samengevoegde tekst behouden. Herstellen observeert alle actuele koppen en schrijft een nieuwe operatie.
- Kloktijden bepalen alleen weergave en back-upplanning, nooit de winnaar van een inhoudelijk conflict.

De volledige causale geschiedenis blijft in snapshots. Er is geen shallow-history garbage collection. Daardoor kunnen ook lang offline gebleven apparaten hun eigen nog niet verstuurde wijzigingen opnieuw samenvoegen.

## Cryptografie en sleutelbeheer

[libsodium](https://doc.libsodium.org/) via `sodium 4.1.2+1`; native versie 1.0.22, browser-sumo 0.8.4 op de in de package gepinde broncommit. De JS/WASM-assets zijn lokaal meegeleverd en controleerbaar met `tool/check_vendor.dart`. Geen cryptografische CDN-afhankelijkheid.

- Willekeurige 256-bits DEK per dataset, gegenereerd door libsodium.
- Wachtwoordsleutel: expliciet **Argon2id v1.3**, 64 MiB, drie iteraties, parallelisme 1, 128-bits willekeurig salt, 256-bits uitvoer. Het versie-2-protocol accepteert uitsluitend deze parameters; door een aanvaller opgegeven kosten kunnen geen onbeperkte KDF-belasting veroorzaken.
- DEK-envelope en wijzigingen: XChaCha20-Poly1305-IETF, verse willekeurige 192-bits nonce per object. Dataset, object-ID, type, protocol, algoritme, nonce en KDF/generatiemetadata zijn AAD.
- Snapshots: libsodium secretstream XChaCha20-Poly1305, 64-KiB-blokken, geauthenticeerde index/context en verplichte eindtag. Truncatie, herordening en verwisselde objecten worden geweigerd.
- Argon2 draait native in een isolate en in de PWA in een eigen Web Worker. Geen wachtwoorden of sleutels in logs, clouddata of tijdelijke bestanden. Native sleutelbuffers worden na gebruik gewist. Dart/JavaScript-strings en een gecompromitteerd proces kunnen niet betrouwbaar worden gewist/beschermd.
- Native DEK en OAuth-refresh-token: platformbeveiligde opslag (Keychain/Keystore, Windows en Linux secret service). macOS gebruikt de legacy Keychain zonder gedeelde sleutelgroep. De PWA gebruikt een **niet-exporteerbare AES-GCM WebCrypto-key in IndexedDB** om lokale geheimen te verpakken; dit is browser-originbescherming, geen OS-keychain of bescherming tegen XSS/gecompromitteerde appupdates.

Wachtwoord wijzigen verpakt dezelfde DEK met nieuwe salt en nonce. Het envelopebestand wordt via Dropbox `rev`/CAS vervangen en teruggelezen/gecontroleerd. Een met de DEK geauthenticeerd overgangsbestand verbindt oude en nieuwe envelopehash/generatie. Reeds ontgrendelde apparaten kunnen zo doorwerken zonder het nieuwe wachtwoord te kennen. Een mislukte concurrente CAS laat hoogstens een ongebruikte geauthenticeerde overgang achter.

Zonder wachtwoord én zonder nog beschikbare DEK is herstel onmogelijk. Een beschikbaar ontgrendeld apparaat kan een nieuw wachtwoord instellen. Rewrapping is **geen intrekking van een gestolen DEK**. Een oude envelope uit Dropbox-versiegeschiedenis kan met het oude wachtwoord nog worden geopend.

## Dropbox-protocol

In de App folder:

```text
/v2/<willekeurige-dataset-id>/key.enc
/v2/<dataset>/changes/<willekeurige-operatie-id>.enc
/v2/<dataset>/snapshots/<willekeurige-snapshot-id>.enc
/v2/<dataset>/transitions/<willekeurige-overgang-id>.enc
```

Geen boektitel, notitietitel of tekst in bestandsnamen. Dropbox ziet wel bestandsgroottes, aantallen, type/pad en verkeersmomenten. Het versleutelde bestandsformaat bevat uitsluitend protocolmetadata buiten de ciphertext. Alleen de cryptografische grenslaag mag uploaden; plaintextsnapshots worden daar geweigerd.

Een immutable upload gebruikt exclusieve `add`, geen autorename. De exacte ciphertext staat vooraf duurzaam in de outbox. Na een verloren antwoord kan dezelfde upload worden herhaald: alleen identieke inhoud of een geauthenticeerde download met dezelfde lokale operatie-inhoud bevestigt ontvangst. Bevestiging en cursors worden pas opgeslagen nadat de ontvangen records lokaal zijn gepubliceerd.

Actieve clients gebruiken `list_folder`, `continue` en `longpoll`; cursors en objectversies blijven lokaal bewaard. Een verlopen cursor veroorzaakt een volledige inventarisatie, geen reset van lokale wijzigingen. Bekende ongewijzigde snapshots worden niet opnieuw gedownload. Wijzigingen worden kort na opslaan verzonden; een periodieke poging herstelt de verbinding. HTTP 429 respecteert Retry-After, tijdelijke fouten krijgen exponentiële vertraging met jitter. OAuth gebruikt PKCE/S256 en refresh tokens zonder app secret.

Android WorkManager en iOS BGProcessing kunnen reeds versleutelde uitgaande wijzigingen transporteren wanneer het OS daarvoor tijd geeft. De taak opent geen gebruikersmap en wijzigt de voorgrondjournal niet. Inkomende gegevens worden bij actief gebruik/hervatten gevalideerd en toegepast. Desktop en PWA hebben geen betrouwbare gesloten-app-taak. Er is geen belofte van directe levering bij gesloten apps.

## Snapshots, herstel en opruimen

Standaard: volledige back-up na 100 wijzigingen of 24 uur tijdens synchronisatie; beleid is instelbaar. Snapshots bevatten manifest, volledige record-/CRDT-geschiedenis en een gecontroleerde operatie-hashlijst. Ze worden teruggedownload, ontsleuteld en volledig gevalideerd vóór bevestiging. Beschadigde herstelpunten blijven behouden voor onderzoek; oudere geldige punten kunnen worden gebruikt.

Herstel maakt expliciet een **afzonderlijk lokaal studieboek**; het vervangt niet stilzwijgend nieuwere gegevens op andere apparaten. Bij koppelen met bestaande lokale inhoud kiest de gebruiker samenvoegen of het oorspronkelijke lokale studieboek apart bewaren. De bron blijft intact, ook bij geannuleerde mapkeuze.

Opschonen maakt eerst een gecontroleerde nieuwe snapshot. Alleen veranderingen die door behouden geldige snapshots worden gedekt, kunnen via revision-voorwaardelijke delete worden verwijderd. Er blijven minstens twee herstelpunten; oudere snapshots worden alleen verwijderd wanneer hun volledige geschiedenis behouden blijft. Onzekere of beschadigde objecten worden niet verwijderd. De volledige lokale geschiedenis en tombstones blijven bestaan.

Eerder bevestigde operatiehashes, envelopehashes en generaties signaleren ontbrekende of teruggezette geschiedenis. **Volledige rollback/verwijdering door een kwaadwillende provider is zonder onafhankelijke vertrouwde toestand niet volledig te bewijzen of te voorkomen**, vooral op een nieuw apparaat. Houd een onafhankelijke reservekopie.

## Grenzen en vrijgave

- Maximaal 20 MiB plaintext per volledige back-up, inclusief geschiedenis/metadata; maximaal 40 MiB per versleuteld transportobject. Dit begrenst geheugen en netwerk, maar is geen onbeperkte notitiecollectie. Een grote database vraagt verdere paginering/streaming van de lokale representatie.
- De eerste Argon2id-browsermeting op de ontwikkelmachine was circa 230 ms. Dit is **geen telefoonbenchmark**. Meet geheugen, responstijd en batterijverbruik op echte Android- en iOS-apparaten en alle desktopdoelen voordat deze parameters als productiekeuze worden vastgezet.
- Voer echte Dropbox-OAuth-, tokenverloop-, quota-, achtergrond-, crash- en iOS-Safari/beginschermtests uit. CI/protocoltestdoubles vervangen deze controles niet.
- Laat de cryptografische protocolkeuzes en migratie onafhankelijk beoordelen. De jonge Loro-binding en auth-plugin-alpha blijven afhankelijkheidsrisico’s.
- De oude plaintext Dropbox-snapshotbestanden worden niet opnieuw geüpload of automatisch gewist. Versleuteling achteraf kan eerder in Dropbox opgeslagen plaintext en versiegeschiedenis niet ongedaan maken. Controleer en verwijder oude kopieën pas nadat nieuwe versleutelde back-ups op een tweede apparaat zijn hersteld.

Referenties: [Dropbox OAuth](https://docs.dropboxapi.com/dropbox-api/docs/oauth), [wijzigingsdetectie](https://docs.dropboxapi.com/dropbox-api/docs/detecting-changes), [Argon2id](https://doc.libsodium.org/password_hashing/default_phf), [secretstream](https://doc.libsodium.org/secret-key_cryptography/secretstream), [Flutter Workmanager](https://docs.page/fluttercommunity/flutter_workmanager/quickstart).
