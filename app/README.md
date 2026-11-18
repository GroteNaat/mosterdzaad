# Flutter-app

De Mosterdzaad-app voor native platforms en de browser. Zie de [projecthandleiding](../README.md) voor gebruik en buildinstructies.

- `lib/domain`: passageparser, datavalidatie en revisiemodel.
- `lib/storage`: studieboekbestanden, IndexedDB, snapshots en afgeleide zoekindex.
- `lib/sync`: Dropbox OAuth/PKCE, API-client en samenvoegen met revision-checked upload.
- `lib/platform`: platformafhankelijke opslag, export en OAuth-redirects.
- `web/`: PWA-manifest, callbackpagina en offline bootstrap.
- `lib/ui`: onboarding, notities, tracker, plannen, studies en instellingen.
- `android/.../MainActivity.kt`: Android Storage Access Framework, persistente URI-rechten.
- `ios/Runner/AppDelegate.swift`: iOS-mapkiezer, security-scoped bookmarks en file coordination.
- `macos/Runner/MainFlutterWindow.swift`: NSOpenPanel, bookmarks en file coordination.
- Windows/Linux: native `file_selector`-dialoog en lokale bestandsopslag.

Geen eigen backend of gebruikersaccounts. Dropbox gebruikt het account van de gebruiker. Zie [PWA](docs/PWA.md) en [Dropbox](docs/DROPBOX.md). Er is geen migratiecode voor de oude Django-app.
