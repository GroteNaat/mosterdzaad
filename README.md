# Mosterdzaad

Een persoonlijke, zelf te hosten Bijbelstudie-app. Lees in je fysieke Bijbel en bewaar hier wat groeit. Geen accounts, geen sociale functies, geen Bijbelteksten, geen externe API nodig tijdens gebruik.

## Wat kun je ermee?

- **Bijbeltracker:** standaard 66 boeken; optioneel deuterocanonieke boeken en toevoegingen. Per boek, hoofdstuk en vers zie je de voortgang.
- **Notities:** koppel één notitie aan meerdere passages, leesplannen, thema’s en bijbelstudies tegelijk. Vanuit elk onderdeel worden de koppelingen vooraf ingevuld.
- **Automatische bundels:** open notities bij een hoofdstuk, vers, thema, plan of studie. Overlappende passages worden bij hetzelfde vers gevonden.
- **Leesplannen:** kies 1–366 sessies en voeg per sessie meerdere passages en een overdenking of vragen toe. Sessies kunnen later worden aangevuld of bewerkt.
- **Bijbelstudies:** leg titel, datum en solo/groep vast. Groepen zijn uitsluitend persoonlijke labels.
- **Export:** download alle inhoud en instellingen als JSON.

Een vers telt alleen als gelezen zolang er minstens één niet-lege notitie aan gekoppeld is. Overlap telt eenmaal. Verwijderen of aanpassen van notities verandert de tracker direct. Een heel hoofdstuk is gelezen zodra alle verzen gedekt zijn. Planvoortgang wordt afgeleid van de passages; een notitie bij alleen een plan markeert geen passages als gelezen.

## Installeren op Ubuntu Server

Benodigd: Git, Docker Engine en de Docker Compose-plugin. Installeer Docker zo nodig volgens de [officiële Ubuntu-instructies](https://docs.docker.com/engine/install/ubuntu/).

```sh
git clone https://github.com/GroteNaat/mosterdzaad.git
cd mosterdzaad
cp .env.example .env
openssl rand -hex 32
openssl rand -hex 32
nano .env
```

Vul de twee verschillende gegenereerde waarden in als `SECRET_KEY` en `POSTGRES_PASSWORD`. Bewaar `.env` privé: het wordt niet opgenomen in Git of de image.

```sh
docker compose up -d --build --wait
docker compose ps
```

De eerste start bouwt de app en maakt automatisch de databasetabellen aan. PostgreSQL bewaart alle gegevens in een Docker-volume. De appcontainer zelf bevat geen persoonlijke inhoud.

### Toegang vanaf je computer

De webapp publiceert standaard **poort 8000 op alle IPv4-netwerkinterfaces** van je Docker-host (`0.0.0.0:8000:8000`). Open vanaf een apparaat op je thuisnetwerk:

```text
http://<LAN-IP-van-je-server>:8000
```

Bijvoorbeeld `http://192.168.1.20:8000`. Je kunt ook de lokale hostnaam van je server gebruiken als je netwerk die naam kan vinden. Er is geen SSH-tunnel nodig. PostgreSQL krijgt geen gepubliceerde poort en blijft binnen het Docker-netwerk.

Deze standaardwaarden staan in `.env.example`:

```dotenv
BIND_ADDRESS=0.0.0.0
PORT=8000
ALLOWED_HOSTS=*
```

Is poort 8000 al in gebruik? Verander `PORT` bijvoorbeeld naar `8085`, voer `docker compose up -d` uit en open `http://192.168.1.20:8085`. De interne containerpoort blijft 8000.

`ALLOWED_HOSTS=*` accepteert iedere servernaam zodat zowel je server-IP als lokale hostnaam direct werkt. Het is geen toegangsfilter voor apparaten. Wil je servernamen beperken, gebruik dan bijvoorbeeld `ALLOWED_HOSTS=localhost,127.0.0.1,192.168.1.20,homelab.local` met je eigen IP/hostnaam. Je kunt `BIND_ADDRESS` ook op je specifieke LAN-IP zetten om uitsluitend die netwerkinterface te gebruiken, of op `127.0.0.1` voor toegang vanaf alleen de server.

Mosterdzaad heeft geen accounts: iedereen die de app kan bereiken kan alle inhoud lezen, aanpassen en exporteren. Deze standaard is bedoeld voor je vertrouwde thuisnetwerk. Gebruik geen router-portforwarding naar deze poort; op een server met een publiek netwerkadres bind je aan het LAN-IP. Docker-gepubliceerde poorten kunnen UFW-regels omzeilen.

Bij een eigen HTTPS-proxy: neem de hostnaam op in `ALLOWED_HOSTS` als je die lijst hebt beperkt, zet `CSRF_TRUSTED_ORIGINS=https://jouw-hostnaam`, `HTTPS=true` en `TRUST_PROXY=true`. Die laatste optie alleen gebruiken als de proxy de `X-Forwarded-Proto`-header zelf betrouwbaar overschrijft. Behoud bij een beperkte hostlijst `127.0.0.1` voor de healthcheck. Alleen `/health/` is uitgezonderd van de HTTPS-doorverwijzing voor de lokale containercontrole; dit endpoint bevat geen persoonlijke inhoud.

### Bestaande installatie vanaf je thuisnetwerk bereikbaar maken

Een bestaande `.env` wordt bij een update niet overschreven. Had je de vorige standaardinstellingen overgenomen, wijzig dan **beide** regels in je bestaande `.env`:

```dotenv
BIND_ADDRESS=0.0.0.0
ALLOWED_HOSTS=*
```

Behoud je `SECRET_KEY`, databasewachtwoord en overige instellingen. Vervolgens:

```sh
git pull --ff-only
docker compose up -d --build --wait
```

Open daarna `http://<LAN-IP-van-je-server>:8000` (of je eigen `PORT`). Je gegevens blijven in het bestaande databasevolume bewaard.

### Updates

Maak eerst een back-up. Daarna:

```sh
git pull --ff-only
docker compose up -d --build --wait
```

Gebruik nooit `docker compose down -v` om te updaten: daarmee verwijder je het databasevolume.

GitHub Actions test de app met PostgreSQL, bouwt en start de Docker-installatie en publiceert bij een geslaagde push naar `main` een image op `ghcr.io/grotenaat/mosterdzaad`. Voor Ubuntu x86-64. Bouwen op de eigen server blijft mogelijk zonder gepubliceerde image. Controleer of Actions ingeschakeld is en of het package voor download openbaar is.

## Back-up en herstel

### Volledige databaseback-up

```sh
mkdir -p backups
docker compose exec -T db pg_dump -U mosterdzaad -d mosterdzaad -Fc > backups/mosterdzaad.dump
```

Bewaar ook `.env` veilig en noteer de gebruikte appversie (`git rev-parse HEAD`). Zet een kopie van je back-ups buiten de server. Maak bijvoorbeeld dagelijks een back-up en controleer periodiek herstel op een aparte installatie.

Terugzetten overschrijft de bestaande database-inhoud. Maak dus eerst een extra back-up. Gebruik bij voorkeur dezelfde appversie:

```sh
docker compose stop app
docker compose exec -T db pg_restore -U mosterdzaad -d mosterdzaad --clean --if-exists --no-owner < backups/mosterdzaad.dump
docker compose start app
```

### JSON-export

Via **Instellingen → Gegevens exporteren** krijg je een leesbare export van alle inhoud. Terugzetten is bedoeld voor een **nieuwe, lege installatie met dezelfde appversie**. Niet samenvoegen met bestaande data: object-ID’s kunnen overlappen. De standaardinstelling die de app bij de eerste pagina maakt, mag wel al bestaan.

Plaats het exportbestand op de server en voer uit:

```sh
docker compose stop app
docker compose run --rm -v "$(pwd)/mosterdzaad-export.json:/tmp/import.json:ro" app python manage.py loaddata /tmp/import.json
docker compose start app
```

## Bijbelnummering

Er worden uitsluitend boeknamen en hoofdstuk-/versaantallen meegeleverd, geen Bijbelteksten. Kies vóór de eerste passage de versindeling die het best bij je fysieke Bijbel past. De standaard is Paratext English; alternatief is de Hebreeuwse/BHS-indeling voor het OT, met ongewijzigd NT en extra boeken. Bij Joël gaat het bijvoorbeeld om 3 versus 4 hoofdstukken. Niet elke vertaling volgt exact één van deze schema’s; sommige uitgaven slaan versnummers over of combineren verzen. De tracker telt de versplaatsen volgens het gekozen schema.

De extra selectie bevat 12 boeken/toevoegingen; Griekse Ester is als afzonderlijk volledig boek opgenomen. De toevoegingen aan Daniël zijn zelfstandige onderdelen. Baruch 6 bevat de Brief van Jeremia. De precieze selectie/plaatsing kan afwijken van jouw Bijbel. Uitschakelen verbergt ze in de tracker, maar verwijdert geen notities of koppelingen.

De versindeling wordt vergrendeld zodra notities of leessessies passages hebben, om stilzwijgende herinterpretatie te voorkomen. Zie [databron en licentie](journal/data/DATA-SOURCES.md).

## Lokale ontwikkeling

Python 3.12. Gebruik een virtuele omgeving en installeer `requirements.txt`. Zonder PostgreSQL-omgevingsvariabelen gebruikt de app een lokale SQLite-database. In productie gebruikt Compose PostgreSQL.

```sh
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export DEBUG=true
python manage.py migrate
python manage.py runserver
```

Windows PowerShell: `.venv\Scripts\Activate.ps1` en `$env:DEBUG='true'` in plaats van de twee overeenkomstige shellopdrachten.

Tests en statische bestanden:

```sh
python manage.py collectstatic --noinput
python manage.py check
python manage.py test
```

Stack: Django 5.2 LTS, HTMX (meegeleverd), CSS, PostgreSQL, Gunicorn en WhiteNoise. De interface blijft bruikbaar zonder JavaScript. Er zijn geen externe fonts, analytics of CDN-verzoeken tijdens gebruik.

## Licenties

Applicatiecode: [MIT](LICENSE), copyright NathanH. Versmetadata: **CC BY-SA 4.0**, zie `journal/data/DATA-SOURCES.md`. HTMX: BSD 2-Clause, zie `static/vendor/HTMX-LICENSE`. Deze afzonderlijke licenties blijven van toepassing op die onderdelen.
