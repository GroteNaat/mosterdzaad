import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../app_controller.dart';
import 'common.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.spa_outlined, color: sage, size: 34),
                    SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'mosterdzaad',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w600,
                          color: sage,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 56),
                Text(
                  'Ruimte om te groeien.',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Een open Bijbel. Een aandachtig hart.\nBewaar je gedachten in je eigen studieboek.',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(height: 1.6),
                ),
                const SizedBox(height: 32),
                if (app.error != null) Notice(app.error!, error: true),
                if (app.busy) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _Choice(
                        icon: Icons.create_new_folder_outlined,
                        title: 'Nieuw studieboek',
                        description:
                            'Begin met een lege verzameling. Kies zelf de map waarin je gegevens worden bewaard.',
                        button: 'Nieuw studieboek maken',
                        onTap: app.busy
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => NewBookDialog(app),
                              ),
                      ),
                      _Choice(
                        icon: Icons.folder_open_outlined,
                        title: 'Bestaand studieboek',
                        description:
                            'Open de map van een studieboek dat je eerder met deze app hebt gemaakt.',
                        button: 'Studieboek openen',
                        onTap: app.busy ? null : app.chooseExisting,
                      ),
                    ];
                    return constraints.maxWidth > 640
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: cards[0]),
                              const SizedBox(width: 16),
                              Expanded(child: cards[1]),
                            ],
                          )
                        : Column(
                            children: [
                              cards[0],
                              const SizedBox(height: 16),
                              cards[1],
                            ],
                          );
                  },
                ),
                const SizedBox(height: 28),
                const Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    _Benefit('Geen account nodig'),
                    _Benefit('Werkt zonder internet'),
                    _Benefit('Jouw bestanden, jouw plek'),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'De app opent de mapkiezer van je apparaat. Maak regelmatig een kopie van je volledige studieboekmap.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.check, size: 16, color: sage),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.description,
    required this.button,
    this.onTap,
  });
  final IconData icon;
  final String title, description, button;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 34, color: sage),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(description, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            onPressed: onTap,
            child: Text(button, textAlign: TextAlign.center),
          ),
        ],
      ),
    ),
  );
}

class NewBookDialog extends StatefulWidget {
  const NewBookDialog(this.app, {super.key});
  final AppController app;
  @override
  State<NewBookDialog> createState() => _NewBookDialogState();
}

class _NewBookDialogState extends State<NewBookDialog> {
  final name = TextEditingController(text: 'Mijn studieboek');
  String scheme = 'english';
  bool extra = false, saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Een nieuw studieboek'),
      content: SizedBox(
        width: 470,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) Notice(error!, error: true),
              TextField(
                controller: name,
                autofocus: true,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Naam van je studieboek',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: scheme,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Hoofdstuk- en versindeling',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'english',
                    child: Text('Paratext English'),
                  ),
                  DropdownMenuItem(
                    value: 'original',
                    child: Text('Hebreeuws / BHS (Oude Testament)'),
                  ),
                ],
                onChanged: saving ? null : (v) => setState(() => scheme = v!),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Deuterocanonieke boeken tonen'),
                value: extra,
                onChanged: saving ? null : (v) => setState(() => extra = v!),
              ),
              const Text(
                'Kies de versindeling die bij je Bijbel past. Die staat vast zodra je passages bewaart. In de gekozen locatie maken we een nieuwe map voor dit studieboek.',
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: 12),
                const Text(
                  'De lokale map Mosterdzaad in Bestanden hoort bij deze app. Kopieer je studieboek naar een andere locatie voordat je de app verwijdert, of kies nu een map in iCloud Drive.',
                ),
              ],
              if (saving)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Annuleren'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text('Locatie kiezen'),
          onPressed: saving
              ? null
              : () async {
                  if (name.text.trim().isEmpty) {
                    setState(() => error = 'Geef je studieboek een naam.');
                    return;
                  }
                  setState(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    await widget.app.create(name.text.trim(), scheme, extra);
                    if (context.mounted && widget.app.repository != null) {
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    if (mounted) setState(() => error = describeError(e));
                  } finally {
                    if (mounted) setState(() => saving = false);
                  }
                },
        ),
      ],
    ),
  );
}
