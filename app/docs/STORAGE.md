# Studieboekformaat v1

De gekozen map is de bron van waarheid:

```text
Mijn studieboek-<id>/
  mosterdzaad.json
  records/
    <revisie-uuid>.md
    <revisie-uuid>.json
```

`mosterdzaad.json` bevat `format: mosterdzaad-studybook`, `version: 1`, een studieboek-UUID, naam en aanmaakdatum. Dit bestand wordt bij het maken geschreven en niet overschreven.

Iedere wijziging maakt een nieuw bestand met een willekeurige revisie-UUID. De envelope bevat `format: mosterdzaad-record`, `version: 1`, de stabiele object-UUID (`id`), `revision`, `parents`, `kind`, UTC-tijd, `deleted` en `data`. Notities gebruiken JSON als YAML-compatible frontmatter tussen twee `---`-regels, gevolgd door de Markdowntekst en een `<!-- mosterdzaad:end -->`-eindmarkering. Die markering helpt een onderbroken schrijfactie herkennen. De andere recordtypen zijn JSON: plan, study, theme, group en preferences.

De huidige versies zijn de bladeren van de revisiegrafiek per object. Er wordt niet automatisch de versie met de nieuwste kloktijd gekozen. Twee bladeren betekenen een conflict; beide blijven behouden totdat de gebruiker een nieuwe versie schrijft met beide revisies als ouders. Verwijderen is een nieuwe revisie met `deleted: true`; herstel maakt weer een gewone revisie. Eerdere versies worden niet fysiek verwijderd.

De app leest vlak vóór schrijven de map opnieuw. Verwachte revisie-ID’s en inhoudshashes beschermen tegen verouderde edits. Nieuwe bestanden worden exclusief aangemaakt, nooit in plaats van een bestaand bestand. Na schrijven wordt de inhoud teruggelezen. Providers kunnen niet allemaal atomisch schrijven; onvolledige bestanden blijven zichtbaar als herstelmelding en blokkeren verdere wijzigingen totdat de map is hersteld. I/O- of toestemmingsfouten worden niet behandeld als een leeg studieboek.

## Herstel

1. Bewaar een kopie van de gehele map voordat je herstelwerk doet.
2. Gebruik bij gewone verwijderingen de prullenbak; bij ongewenste edits de versiegeschiedenis.
3. Kies bij een conflict expliciet een versie. Kopieer zo nodig tekst uit beide versies voordat je kiest.
4. Herstel bij onvolledige/ontbrekende revisies de map uit een consistente back-up. Verwijder niet willekeurig eerdere revisies: latere bestanden verwijzen naar hun ouders.
5. Bij een ontbrekende of verplaatste locatie kies je opnieuw de map met `mosterdzaad.json`.

De SQLite-index is alleen een cache op het apparaat. Bij het openen wordt deze opnieuw gevuld. Er worden geen actieve SQLitebestanden in een cloudmap gedeeld. De cache bevat tekst en moet, net als het studieboek, als persoonlijke gegevens worden behandeld.

## Platformtoegang

Android bewaart de oorspronkelijke SAF-tree-URI en de document-ID van de studieboekmap. De persistente grant hoort bij de oorspronkelijke geselecteerde tree. Een content-URI wordt niet omgezet in een verzonnen lokaal bestandspad.

Apple bewaart een security-scoped bookmark en activeert die tijdens bewerkingen. Lezen en schrijven gebruikt NSFileCoordinator. Een stale bookmark of ingetrokken toegang geeft een fout en vraagt opnieuw mapkeuze. De macOS-app heeft sandboxrechten voor door de gebruiker geselecteerde bestanden en bookmarks.

Windows/Linux gebruiken normale lokale paden. Een locatie mag verdwijnen (losgekoppelde schijf, verplaatste map); de app maakt dan niet automatisch een vervangende database.

## Grenzen

Deze versie heeft geen ingebouwde versleuteling, realtime samenwerking of automatische cloudsync. Er is geen prullenbak legen of geschiedenis opruimen: dat voorkomt dat synchronisatie of herstel nog benodigde ouders verliest. Handmatige edits aan revisiebestanden zijn geen ondersteunde manier om nieuwe revisies te maken. Oudere Django-JSON-exports en SQLite-databases worden niet geïmporteerd.
