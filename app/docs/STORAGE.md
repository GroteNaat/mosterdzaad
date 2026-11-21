# Lokale studieboeken en herstel

De gekozen map blijft de onversleutelde bron van waarheid. In de PWA staat dezelfde inhoud in IndexedDB. De native SQLite-zoekindex en browserzoekindex zijn afgeleide caches; ze bevatten leesbare persoonlijke tekst.

```text
mosterdzaad.json
records/
  format-v2.json
  <poging-uuid>.pending
  <poging-uuid>.commit
  <oude-revisie-uuid>.md|json
```

Het manifest (mosterdzaad-studybook, versie 1) houdt de oorspronkelijke boek-ID, naam en aanmaakdatum. Nieuwe records zijn versie 2, met object-ID, operatie-/revisie-ID, causale ouders, apparaat-actor, oorspronkelijke aanmaakdatum, tombstone en een Loro-update. De volledige lokale tekst staat er ook in. Notities gebruiken JSON-frontmatter en Markdown met een eindmarkering; andere records zijn JSON.

Een write maakt eerst een nieuwe .pending-poging, leest die volledig terug en publiceert vervolgens een .commit-marker met bestandsnaam en SHA-256. Alleen een complete marker publiceert de wijziging. Een crash vóór publicatie laat de vorige toestand geldig; een retry gebruikt een nieuwe poging-ID. Een beschadigde gepubliceerde wijziging veroorzaakt een fout, nooit een lege vervangende database. Ontvangen batches worden eerst volledig gevalideerd en daarna in causale volgorde gepubliceerd. Onderbroken batches kunnen veilig opnieuw worden aangeboden.

V1-revisies blijven ongewijzigd en worden deterministisch naar Loro-bewerkingen vertaald bij lezen. format-v2.json zorgt dat oude clients het boek als niet-ondersteund behandelen en schrijven/synchroniseren blokkeren. Open een bijgewerkt studieboek niet met een oudere app. Er is geen import uit de oude Django-app toegevoegd.

Loro voegt tekst en koppelingen samen. Verschillende gelijktijdige metadatawaarden blijven als alternatieven zichtbaar. Verwijderen wint van een gelijktijdige edit, met de samengestelde tekst in de prullenbak. Expliciet herstellen schrijft een nieuwe operatie; eerdere versies blijven behouden. Zie [het protocol](ENCRYPTED-SYNC.md) voor de precieze regels.

## Back-ups

Kopieer de **hele map**, inclusief commitmarkers en pending-bestanden waarnaar ze verwijzen. De PWA kan een plaintextreservekopie downloaden; behandel dat bestand als persoonlijke gegevens. Cloudback-ups zijn afzonderlijk versleuteld.

Het portable formaat mosterdzaad-snapshot, versie 1, bevat uitsluitend het manifest en canonieke records/<revision>.md|json-inhoud. De lokale commitstructuur wordt hiervoor uitgepakt. Maprechten, SQLite, OAuth en DEK ontbreken. Herstel valideert alle records, ouders en de acyclische grafiek en publiceert het manifest als laatste in een nieuwe map. Een cloudherstelpunt wordt als afzonderlijk boek geopend zodat nieuwere wijzigingen behouden blijven.

Een volledige cloudback-up inclusief CRDT-geschiedenis en controlemetadata is maximaal 20 MiB. Individuele lokale records zijn begrensd tot 8 MiB. Geschiedenis blijft behouden tot expliciet definitief verwijderen. Handmatige edits zijn geen ondersteunde manier om nieuwe wijzigingen te maken.

## Definitief verwijderen

De prullenbak heeft naast **Terugzetten** een knop **Definitief verwijderen**, met een bevestigingsvenster. Dit schrijft eerst een duurzaam `purge`-record met uitsluitend willekeurige object-/revisie-ID's, het onderdeeltype en hashes. Er staat geen titel, tekst of Loro-update van het gewiste onderdeel in dit bewijs. Daarna verdwijnen alle lokale revisies van dat onderdeel, inclusief tombstones, publicatiemarkers en achtergebleven complete pending-bestanden. Bij een onderbreking wordt het opruimen bij opnieuw openen hervat. De zoekindex wordt opnieuw opgebouwd met SQLite `secure_delete` en gecompacteerd.

Een oude bewerking of reservekopie met dezelfde object-ID kan het onderdeel niet terugbrengen. Cloudherstelpunten krijgen de actuele wisbewijzen toegepast voordat een afzonderlijk hersteld boek nieuwe ID's krijgt. Leesplansessies houden bij kopiëren hun koppelingen met notities.

Bij synchronisatie wordt eerst een nieuwe, gecontroleerde back-up gemaakt waarin de overige geschiedenis bewaard blijft. Daarna verwijdert de app de bijbehorende wijzigingsbestanden en oude back-ups uit de actieve Dropbox-map. Als een beschadigde back-up niet gecontroleerd kan worden, meldt synchronisatie dat het wissen in Dropbox nog niet volledig is afgerond. Offline apparaten wissen hun lokale kopieën bij de volgende voorgrondsynchronisatie. Een versleuteld wiskenmerk voorkomt dat een nog niet bijgewerkte achtergrondtaak oude wijzigingen blind uploadt; een reeds lopende aanvraag kan pas bij een volgende synchronisatie worden opgeruimd.

Gebruik hiervoor **0.4.0 of nieuwer op alle apparaten**. Oudere apps begrijpen het nieuwe recordtype niet. Een volledige kopie die eerder is geëxporteerd, een ander studieboek met andere ID's en systeem-/providerback-ups vallen buiten de wisprocedure. Het verwijderen van bestanden is geen forensisch gegarandeerd overschrijven van schijf-, browser- of geheugensectoren.

**Dropbox bewaart zelf herstelgeschiedenis.** De API voor direct permanent wissen is alleen beschikbaar voor Dropbox Business-apps; deze App folder-koppeling kan die niet gebruiken. Verwijder resterende herstelkopieën in Dropbox handmatig als die ook onherstelbaar weg moeten. Zie [Dropbox permanent-delete API](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/files/permanently-delete) en [bestanden definitief verwijderen](https://help.dropbox.com/delete-restore/delete-files).

## Sleutels, status en platformtoegang

De per-apparaat synchronisatiejournal staat buiten de studieboekmap in app-supportopslag, of in de IndexedDB-settings-store. Hij bevat cursor, bevestigde hashes en een versleutelde outbox. Native statusupdates worden via een geschreven en geflushte tijdelijke versie vervangen; schrijfacties per sleutel worden geserialiseerd. OAuth-refresh-token en DEK staan in aparte beveiligde opslag, nooit in de journal of exports.

Android gebruikt de oorspronkelijke SAF-tree-URI en persistente grant. Apple gebruikt security-scoped bookmarks en NSFileCoordinator. Windows/Linux gebruiken echte lokale paden. Een ingetrokken toestemming of verdwenen schijf wordt niet als een leeg boek behandeld.

De browser vraagt persistente opslag aan, maar de browser mag dat weigeren. Websitegegevens wissen of opslagdruk kan zowel notities als lokale sleutels verwijderen. De service-worker-cache bevat uitsluitend appassets. Houd een werkende back-up en bewaar het versleutelingswachtwoord onafhankelijk.
