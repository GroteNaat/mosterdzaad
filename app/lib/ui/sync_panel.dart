import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../storage/vault_snapshot.dart';
import '../sync/encrypted_sync.dart';
import 'common.dart';

class SyncPanel extends StatelessWidget {
  const SyncPanel(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final disabled = app.busy || app.syncing;
    final status = app.syncing
        ? 'Synchroniseren…'
        : app.syncOffline
        ? 'Offline — wijzigingen staan in de wachtrij'
        : app.syncError != null
        ? 'Synchronisatie heeft aandacht nodig'
        : app.syncEnabled && app.pendingChanges > 0
        ? '${app.pendingChanges} wijzigingen in de wachtrij'
        : app.syncEnabled && app.lastSynced != null
        ? 'Alles gesynchroniseerd'
        : 'Nog niet gekoppeld';
    String date(DateTime time) =>
        '${shortDate(time)} ${time.toLocal().toString().substring(11, 16)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dropbox-synchronisatie en back-up',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Je werkt altijd lokaal. We synchroniseren bij openen, terugkeren naar de app en kort na opslaan. Wijzigingen en herstelpunten worden eerst op je apparaat versleuteld.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  app.syncOffline
                      ? Icons.cloud_off_outlined
                      : app.syncEnabled
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(status)),
              ],
            ),
            if (app.syncing) const LinearProgressIndicator(),
            if (app.syncError != null) Notice(app.syncError!, error: true),
            if (app.lastSynced != null)
              Text('Laatst gesynchroniseerd: ${date(app.lastSynced!)}'),
            if (app.lastBackup != null)
              Text('Laatste volledige back-up: ${date(app.lastBackup!)}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (app.repository != null)
                  FilledButton.icon(
                    onPressed: disabled
                        ? null
                        : () => app.syncEnabled
                              ? app.run(() => app.syncNow(rethrowErrors: true))
                              : linkStudyBook(context, app),
                    icon: Icon(
                      app.syncEnabled ? Icons.sync : Icons.lock_outline,
                    ),
                    label: Text(
                      app.syncEnabled
                          ? 'Nu synchroniseren'
                          : 'Dit studieboek koppelen',
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: disabled
                      ? null
                      : () => openDropboxBooks(context, app),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Uit Dropbox openen'),
                ),
                if (app.syncEnabled) ...[
                  OutlinedButton(
                    onPressed: disabled ? null : () => app.run(app.backupNow),
                    child: const Text('Nu back-up maken'),
                  ),
                  OutlinedButton(
                    onPressed: disabled
                        ? null
                        : () => showRestorePoints(context, app),
                    child: const Text('Back-up herstellen'),
                  ),
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () => app.run(() async {
                            final password = await encryptionPassword(
                              context,
                              create: true,
                              changing: true,
                            );
                            if (password != null) {
                              await app.changeSyncPassword(password);
                            }
                          }),
                    child: const Text('Wachtwoord wijzigen'),
                  ),
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () => backupPolicy(context, app),
                    child: const Text('Back-upinstellingen'),
                  ),
                ],
                if (app.dropboxConnected)
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () => app.run(app.disconnectDropbox),
                    child: const Text('Verbinding verbreken'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Tijdens gebruik worden wijzigingen automatisch uitgewisseld. Als de app gesloten is, bepaalt het besturingssysteem wanneer synchronisatie kan plaatsvinden.',
              style: TextStyle(color: Colors.black54),
            ),
            if (kIsWeb)
              const Text(
                'Deze browser onthoudt de koppeling met WebCrypto. Gebruik een vertrouwd apparaat. Browsergegevens wissen verwijdert ook de lokale sleutel; bewaar je wachtwoord in een wachtwoordmanager.',
                style: TextStyle(color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> encryptionPassword(
  BuildContext context, {
  required bool create,
  bool changing = false,
}) async {
  final password = TextEditingController(),
      confirmation = TextEditingController();
  final form = GlobalKey<FormState>();
  var understood = false;
  try {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            changing
                ? 'Nieuw versleutelingswachtwoord'
                : create
                ? 'Beveilig je Dropbox-kopie'
                : 'Studieboek ontgrendelen',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      create
                          ? 'Kies een lang, uniek wachtwoord en bewaar het in je wachtwoordmanager. Mosterdzaad kan het niet terughalen.'
                          : 'Gebruik het versleutelingswachtwoord van dit studieboek. Dit is niet je Dropbox-wachtwoord.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Versleutelingswachtwoord',
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Vul je wachtwoord in.'
                          : create && value.length < 12
                          ? 'Gebruik minstens 12 tekens.'
                          : null,
                    ),
                    if (create) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmation,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Herhaal het wachtwoord',
                        ),
                        validator: (value) => value != password.text
                            ? 'De wachtwoorden verschillen.'
                            : null,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: understood,
                        onChanged: (value) =>
                            setState(() => understood = value ?? false),
                        title: const Text(
                          'Ik begrijp dat ik zonder dit wachtwoord én zonder een ontgrendeld apparaat mijn gegevens niet kan herstellen.',
                        ),
                      ),
                    ],
                    if (changing)
                      const Text(
                        'Je andere ontgrendelde apparaten blijven gekoppeld. Een oud wachtwoordbestand uit Dropbox-versiegeschiedenis kan met het oude wachtwoord nog worden geopend.',
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: create && !understood
                  ? null
                  : () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(context, password.text);
                      }
                    },
              child: Text(create ? 'Beveiligen' : 'Ontgrendelen'),
            ),
          ],
        ),
      ),
    );
  } finally {
    password.dispose();
    confirmation.dispose();
  }
}

Future<void> linkStudyBook(BuildContext context, AppController app) =>
    app.run(() async {
      if (!app.dropboxConnected) await app.connectDropbox();
      final books = await app.cloudBooks();
      if (!context.mounted) return;
      if (books.isNotEmpty) {
        final useExisting = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Er staan al studieboeken in Dropbox'),
            content: const Text(
              'Open een bestaand studieboek om hetzelfde boek op meerdere apparaten te gebruiken, of maak een afzonderlijke versleutelde kopie van dit lokale boek.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuleren'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Nieuwe kopie'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Bestaand openen'),
              ),
            ],
          ),
        );
        if (useExisting == null || !context.mounted) return;
        if (useExisting) {
          await chooseCloudBook(context, app, books);
          return;
        }
      }
      final password = await encryptionPassword(context, create: true);
      if (password != null) await app.enableSync(password);
    });

Future<void> openDropboxBooks(BuildContext context, AppController app) =>
    app.run(() async {
      if (!app.dropboxConnected) await app.connectDropbox();
      final books = await app.cloudBooks();
      if (context.mounted) await chooseCloudBook(context, app, books);
    });

Future<void> chooseCloudBook(
  BuildContext context,
  AppController app,
  List<String> books,
) async {
  final id = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Versleutelde studieboeken'),
      children: books.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nog geen versleutelde studieboeken gevonden. Open een lokaal boek en kies ‘Dit studieboek koppelen’.',
                ),
              ),
            ]
          : [
              for (final id in books)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, id),
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text('Studieboek ${id.substring(0, 8)}'),
                    subtitle: const Text(
                      'De naam wordt zichtbaar na ontgrendelen.',
                    ),
                  ),
                ),
            ],
    ),
  );
  if (id == null || !context.mounted) return;
  var merge = false;
  if (app.repository != null) {
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Je huidige lokale gegevens'),
        content: const Text(
          'Je huidige studieboek blijft als afzonderlijke lokale kopie bewaard. Wil je de inhoud ook samenvoegen met het Dropbox-studieboek?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Alleen apart bewaren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ook samenvoegen'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    merge = choice;
  }
  final password = await encryptionPassword(context, create: false);
  if (password != null) await app.openCloud(id, password, mergeLocal: merge);
}

Future<void> showRestorePoints(
  BuildContext context,
  AppController app,
) => app.run(() async {
  final points = await app.restorePoints();
  if (!context.mounted) return;
  final point = await showDialog<RestorePoint>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Kies een herstelpunt'),
      content: SizedBox(
        width: 480,
        height: 330,
        child: points.isEmpty
            ? const Text('Nog geen geldige volledige back-up beschikbaar.')
            : ListView(
                children: [
                  const Text(
                    'Herstel maakt een afzonderlijk lokaal studieboek. Je huidige boek en nieuwere wijzigingen blijven beschikbaar.',
                  ),
                  for (final point in points)
                    ListTile(
                      title: Text(
                        '${shortDate(point.created)} ${point.created.toLocal().toString().substring(11, 16)}',
                      ),
                      subtitle: Text(
                        '${point.covered.length} opgeslagen wijzigingen',
                      ),
                      onTap: () => Navigator.pop(context, point),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuleren'),
        ),
      ],
    ),
  );
  if (point != null) await app.restorePoint(point);
});

Future<void> backupPolicy(BuildContext context, AppController app) async {
  var hours = 24, operations = 100, retention = 7;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Back-upinstellingen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Een volledige back-up wordt gemaakt zodra één van deze grenzen wordt bereikt tijdens synchronisatie.',
            ),
            DropdownButton<int>(
              value: hours,
              isExpanded: true,
              items: [
                for (final n in [1, 6, 12, 24, 48, 168])
                  DropdownMenuItem(value: n, child: Text('Elke $n uur')),
              ],
              onChanged: (n) => setState(() => hours = n!),
            ),
            DropdownButton<int>(
              value: operations,
              isExpanded: true,
              items: [
                for (final n in [25, 100, 500, 1000])
                  DropdownMenuItem(value: n, child: Text('Na $n wijzigingen')),
              ],
              onChanged: (n) => setState(() => operations = n!),
            ),
            DropdownButton<int>(
              value: retention,
              isExpanded: true,
              items: [
                for (final n in [2, 7, 14, 30, 100])
                  DropdownMenuItem(
                    value: n,
                    child: Text('$n herstelpunten bewaren'),
                  ),
              ],
              onChanged: (n) => setState(() => retention = n!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Opslaan en veilig opschonen'),
          ),
        ],
      ),
    ),
  );
  if (save == true) {
    await app.run(() async {
      await app.setBackupPolicy(hours, operations, retention);
      await app.compactBackups();
    });
  }
}

Future<void> openLocalBooks(BuildContext context, AppController app) async {
  if (!kIsWeb) {
    await app.chooseExisting();
    return;
  }
  await app.run(() async {
    final books = await app.picker.listBooks();
    if (!context.mounted) return;
    final location = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Studieboeken in deze browser'),
        children: books.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Er zijn nog geen studieboeken. Maak een nieuw boek of open een kopie uit Dropbox.',
                  ),
                ),
              ]
            : [
                for (var i = 0; i < books.length; i++)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, i),
                    child: Text(books[i].label),
                  ),
              ],
      ),
    );
    if (location != null) await app.open(books[location]);
  });
}

Future<void> importBackup(AppController app) => app.run(() async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'Mosterdzaad-reservekopie',
        extensions: ['json'],
        mimeTypes: ['application/json'],
        uniformTypeIdentifiers: ['public.json'],
      ),
    ],
  );
  if (file == null) return;
  if (await file.length() > VaultSnapshot.maxBytes) {
    throw const FormatException('De reservekopie is groter dan 20 MB.');
  }
  await app.restoreSnapshot(VaultSnapshot.decode(await file.readAsString()));
});
