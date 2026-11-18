# Flutter-app

De native Mosterdzaad-app. Zie de [projecthandleiding](../README.md) voor gebruik en buildinstructies.

- `lib/domain`: passageparser, datavalidatie en revisiemodel.
- `lib/storage`: studieboekbestanden, heropenen en afgeleide SQLite-index.
- `lib/ui`: onboarding, notities, tracker, plannen, studies en instellingen.
- `android/.../MainActivity.kt`: Android Storage Access Framework, persistente URI-rechten.
- `ios/Runner/AppDelegate.swift`: iOS-mapkiezer, security-scoped bookmarks en file coordination.
- `macos/Runner/MainFlutterWindow.swift`: NSOpenPanel, bookmarks en file coordination.
- Windows/Linux: native `file_selector`-dialoog en lokale bestandsopslag.

Geen webtarget, backend, gebruikersaccounts of migratiecode voor de oude app.
