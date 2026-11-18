import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import '../app_controller.dart';
import '../storage/vault_snapshot.dart';
import '../sync/dropbox_client.dart';
import 'common.dart';

class SyncPanel extends StatelessWidget {
  const SyncPanel(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final disabled = app.busy || app.syncing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dropbox', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const Text(
              'Bewaar een kopie in je eigen Dropbox en gebruik hetzelfde studieboek op meerdere apparaten. Je kunt altijd offline verderwerken.',
            ),
            const SizedBox(height: 10),
            if (app.syncing) const LinearProgressIndicator(),
            if (app.syncError != null) Notice(app.syncError!, error: true),
            if (app.lastSynced != null)
              Text(
                'Laatst gesynchroniseerd: ${shortDate(app.lastSynced!)} ${app.lastSynced!.toLocal().toString().substring(11, 16)}',
              ),
            if (!app.dropboxConnected)
              const Text(
                'Aanmelden geldt voor deze appsessie. Na opnieuw openen of het verlopen van de sessie meld je opnieuw aan.',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (app.repository != null)
                  FilledButton.icon(
                    onPressed: disabled ? null : () => app.run(app.enableSync),
                    icon: Icon(
                      app.syncEnabled && app.dropboxConnected
                          ? Icons.sync
                          : Icons.cloud_outlined,
                    ),
                    label: Text(
                      app.syncEnabled && app.dropboxConnected
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
                if (app.dropboxConnected)
                  TextButton(
                    onPressed: disabled ? null : app.disconnectDropbox,
                    child: const Text('Verbinding verbreken'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Synchroniseert terwijl de app open is. De inhoud in Dropbox is niet door Mosterdzaad versleuteld.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
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

Future<void> openDropboxBooks(
  BuildContext context,
  AppController app,
) => app.run(() async {
  if (!app.dropboxConnected) await app.connectDropbox();
  final books = await app.cloudBooks();
  if (!context.mounted) return;
  final snapshot = await showDialog<VaultSnapshot>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Je studieboeken in Dropbox'),
      content: SizedBox(
        width: 520,
        height: 350,
        child: books.isEmpty
            ? const Text(
                'Nog geen studieboeken gevonden. Open eerst een lokaal studieboek en kies bij Instellingen voor ‘Dit studieboek koppelen’.',
              )
            : ListView.builder(
                itemCount: books.length,
                itemBuilder: (_, i) => _CloudBookTile(app, books[i]),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Sluiten'),
        ),
      ],
    ),
  );
  if (snapshot != null) await app.restoreSnapshot(snapshot, fromDropbox: true);
});

class _CloudBookTile extends StatefulWidget {
  const _CloudBookTile(this.app, this.book);
  final AppController app;
  final CloudBook book;
  @override
  State<_CloudBookTile> createState() => _CloudBookTileState();
}

class _CloudBookTileState extends State<_CloudBookTile> {
  late final Future<VaultSnapshot> snapshot = widget.app.cloudSnapshot(
    widget.book.id,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<VaultSnapshot>(
    future: snapshot,
    builder: (context, result) => ListTile(
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(
        result.data?.name ?? 'Studieboek ${widget.book.id.substring(0, 8)}',
      ),
      subtitle: Text(
        result.hasError
            ? describeError(result.error!)
            : result.hasData
            ? 'Bijgewerkt ${shortDate(DateTime.parse(widget.book.modified))}'
            : 'Studieboek lezen…',
      ),
      onTap: result.hasData ? () => Navigator.pop(context, result.data) : null,
    ),
  );
}
