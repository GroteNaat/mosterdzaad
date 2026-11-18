# Hoofdstuk- en versmetadata

Deze bestanden bevatten uitsluitend boektitels, alternatieve namen en aantallen verzen per hoofdstuk. Er is geen Bijbeltekst opgenomen.

## Bron en licentie

Bron: Copenhagen Alliance, Versification Working Group, standaardversificaties uit Paratext.

- Repository: https://github.com/Copenhagen-Alliance/versification-specification
- Vastgelegde commit: `519af776ab65d89a51e37f750779250f940459ef`
- Bronbestand: `versification-mappings/standard-mappings/eng.json` voor `books.json`.
- `books-original.json` gebruikt `versification-mappings/standard-mappings/org.json` voor de 39 OT-boeken en `eng.json` voor het NT en de optionele DC-boeken. Deze samengestelde variant past bij de instelling 'Hebreeuwse versindeling (OT)' en behoudt Baruch 6 inclusief Brief van Jeremia.
- Engelse versificatie: Reinier de Blois en Neil Rees ('Studge').
- Original-versificatie: Neil Rees ('Studge').
- Datalicentie: **Creative Commons Attribution-ShareAlike 4.0 International**, https://creativecommons.org/licenses/by-sa/4.0/ . De gegevensbestanden en wijzigingen daarin worden onder diezelfde licentie verspreid. Deze datalicentie staat los van de licentie van de applicatiecode.
- Bronlicentie: https://github.com/Copenhagen-Alliance/versification-specification/blob/519af776ab65d89a51e37f750779250f940459ef/LICENSE.md

Wijzigingen: selectie van 78 boeken uit de bron, Nederlandse namen en zoekaliassen toegevoegd, aantallen omgezet van tekst naar getallen en het onderscheid OT/NT/DC toegevoegd. `chapters[0]` is het maximum versnummer in hoofdstuk 1.

## Versnummering en canon

De eerste 66 items zijn de gebruikelijke protestantse canon in Nederlandse boekvolgorde. Daarna volgen 12 optionele onderdelen: Tobit, Judit, Wijsheid, Sirach, Baruch, 1 en 2 Makkabeeën, Griekse Ester, Gebed van Azarja, Susanna, Bel en de draak, Gebed van Manasse. Deze selectie is bedoeld als praktische verzameling optionele boeken en toevoegingen, niet als definitie van één kerkelijke canon.

`books.json` volgt de Paratext English-versificatie. Dit is een expliciete referentiestandaard, geen claim dat alle Nederlandse uitgaven exact dezelfde nummering gebruiken. `books-original.json` volgt de BHS-versificatie voor het OT; het NT en de extra boeken blijven gelijk aan English. In de BHS-versificatie heeft Joël bijvoorbeeld 4 hoofdstukken, terwijl de English-versificatie 3 heeft. Ook versnummering in Psalmen en Maleachi verschilt. Exacte ondersteuning voor een bepaalde Nederlandse Bijbeluitgave vereist een passende, geteste versificatie voor die uitgave.

In beide meegeleverde varianten telt Baruch 6 hoofdstukken; hoofdstuk 6 is de Brief van Jeremia. De Brief is daarom niet nogmaals afzonderlijk opgenomen. De app staat wisselen van versificatie alleen toe zolang er nog geen passages aan notities of leessessies gekoppeld zijn.

Ester (Grieks) bevat de volledige Griekse Ester in 10 genummerde hoofdstukken, niet uitsluitend de zes toevoegingen A-F. Gebed van Azarja, Susanna en Bel en de draak worden als afzonderlijke delen weergegeven. In sommige gedrukte uitgaven zijn deze teksten onderdeel van Daniël (hoofdstuk 3 en/of 13-14). De tracker kan die verschillen niet zonder expliciete omzetting gelijkstellen.

Het gaat om maximum versnummers (versplaatsen): sommige vertalingen slaan nummers over of plaatsen ze tussen haken. Daaruit volgt dat een teller niet automatisch het precieze aantal afgedrukte verzen in iedere fysieke uitgave weergeeft.
