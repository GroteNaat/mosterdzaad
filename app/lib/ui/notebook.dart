import 'package:material_ui/material_ui.dart';
import '../app_controller.dart';
import '../domain/bible.dart';
import '../domain/entry.dart';
import 'common.dart';
import 'editor.dart';
import 'sync_panel.dart';
import 'package:flutter/foundation.dart';

class NotebookShell extends StatefulWidget {
  const NotebookShell(this.app, {super.key});
  final AppController app;
  @override
  State<NotebookShell> createState() => _NotebookShellState();
}

class _NotebookShellState extends State<NotebookShell>
    with WidgetsBindingObserver {
  int page = 0;
  static const labels = [
    'Overzicht',
    'Bijbeltracker',
    'Notities',
    'Leesplannen',
    'Bijbelstudies',
    'Thema’s',
    'Instellingen',
  ];
  static const icons = [
    Icons.spa_outlined,
    Icons.menu_book_outlined,
    Icons.edit_note,
    Icons.calendar_month_outlined,
    Icons.groups_outlined,
    Icons.sell_outlined,
    Icons.settings_outlined,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.app.repository != null &&
        !widget.app.busy) {
      widget.app.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final child = switch (page) {
      0 => OverviewPage(app),
      1 => TrackerPage(app),
      2 => NotesPage(app),
      3 => CollectionPage(app, 'plan'),
      4 => CollectionPage(app, 'study'),
      5 => CollectionPage(app, 'theme'),
      _ => SettingsPage(app),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(app.repository!.name),
        actions: [
          if (app.syncEnabled)
            IconButton(
              tooltip:
                  app.syncError ??
                  (app.syncing
                      ? 'Synchroniseren…'
                      : 'Synchroniseren met Dropbox'),
              onPressed: app.syncing ? null : app.syncNow,
              icon: Icon(
                app.syncError != null
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
              ),
            ),
          if (app.busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Studieboek vernieuwen',
            onPressed: app.busy ? null : app.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Nieuwe notitie',
            onPressed: () => editEntry(context, app, 'note'),
            icon: const Icon(Icons.note_add_outlined),
          ),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'mosterdzaad',
                        style: TextStyle(fontSize: 27, color: sage),
                      ),
                    ),
                    for (var i = 0; i < labels.length; i++)
                      ListTile(
                        leading: Icon(icons[i]),
                        title: Text(labels[i]),
                        selected: page == i,
                        onTap: () {
                          setState(() => page = i);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              NavigationRail(
                extended: true,
                minExtendedWidth: 218,
                selectedIndex: page,
                onDestinationSelected: (i) => setState(() => page = i),
                leading: const Padding(
                  padding: EdgeInsets.fromLTRB(12, 20, 12, 28),
                  child: Text(
                    'mosterdzaad',
                    style: TextStyle(
                      fontSize: 25,
                      color: sage,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                destinations: [
                  for (var i = 0; i < labels.length; i++)
                    NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(labels[i]),
                    ),
                ],
              ),
            Expanded(
              child: Column(
                children: [
                  if (app.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Notice(app.error!, error: true),
                    ),
                  if (app.repository!.warnings.isNotEmpty ||
                      app.repository!.conflicts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Notice(
                        'Je studieboek heeft bestanden die aandacht nodig hebben. Bekijk Instellingen → Herstel en geschiedenis.',
                        error: true,
                      ),
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PageBody extends StatelessWidget {
  const PageBody(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        children: children,
      ),
    ),
  );
}

class OverviewPage extends StatelessWidget {
  const OverviewPage(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final books = app.bible.books(
      app.repository!.scheme,
      extra: app.repository!.extra,
    );
    final c = app.covered;
    final total = books.fold(0, (n, b) => n + b.verseCount);
    final done = books.fold(
      0,
      (n, b) =>
          n +
          List.generate(
            b.chapters.length,
            (i) => c['${b.code}:${i + 1}']?.length ?? 0,
          ).fold(0, (a, v) => a + v),
    );
    return PageBody([
      PageHeading(
        'Ruimte om te groeien.',
        'Lees, verwonder en bewaar wat je raakt.',
        action: FilledButton.icon(
          onPressed: () => editEntry(context, app, 'note'),
          icon: const Icon(Icons.add),
          label: const Text('Nieuwe notitie'),
        ),
      ),
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFFE9EDE2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.spa_outlined, size: 46, color: sage),
            SizedBox(height: 20),
            Text(
              'Een open Bijbel.\nEen aandachtig hart.',
              style: TextStyle(
                fontSize: 31,
                height: 1.3,
                color: Color(0xFF31402D),
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Je hoeft niet alles tegelijk te ontdekken.\nBegin met een passage en schrijf op wat je opvalt.',
              style: TextStyle(height: 1.7),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _Stat('$done', 'Verzen met een notitie'),
          _Stat('${app.ofKind('note').length}', 'Bewaarde gedachten'),
          _Stat('${app.ofKind('study').length}', 'Bijbelstudies'),
        ],
      ),
      const SizedBox(height: 24),
      Text(
        'Jouw weg door de Bijbel',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: total == 0 ? 0 : done / total,
        minHeight: 8,
        borderRadius: BorderRadius.circular(8),
      ),
      const SizedBox(height: 8),
      Text(
        '${(100 * done / total).toStringAsFixed(1)}% van de verzen heeft een notitie. Je bepaalt zelf je ritme.',
      ),
      const SizedBox(height: 32),
      Text('Laatste gedachten', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (app.ofKind('note').isEmpty)
        EmptyState(
          'Hier begint je verzameling.',
          'Kies een passage, thema, leesplan of studie en schrijf je eerste gedachte.',
          action: TextButton(
            onPressed: () => editEntry(context, app, 'note'),
            child: const Text('Schrijf een notitie'),
          ),
        ),
      for (final n in app.ofKind('note').take(5)) NoteCard(app, n),
      const SizedBox(height: 20),
      Text(
        kIsWeb
            ? 'Opgeslagen in deze browser'
            : 'Opgeslagen in ${app.repository!.files.location.label}',
        style: const TextStyle(color: Colors.black54),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 35,
                color: sage,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class NoteCard extends StatelessWidget {
  const NoteCard(this.app, this.note, {super.key});
  final AppController app;
  final Entry note;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(20),
      title: Text(
        note.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              note.text('body'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Text(
              [
                if (note.text('references').isNotEmpty)
                  note.text('references').replaceAll('\n', ' · '),
                shortDate(note.updated),
              ].join(' · '),
              style: const TextStyle(color: sage),
            ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => openDetail(context, app, note.id),
    ),
  );
}

class NotesPage extends StatefulWidget {
  const NotesPage(this.app, {super.key});
  final AppController app;
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  String query = '';
  Set<String>? matches;
  int generation = 0;
  Future<void> search(String value) async {
    final request = ++generation;
    setState(() => query = value);
    final result = await widget.app.search(value);
    if (mounted && request == generation) setState(() => matches = result);
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.app
        .ofKind('note')
        .where((n) => query.isEmpty || matches?.contains(n.id) == true)
        .toList();
    return PageBody([
      PageHeading(
        'Notities',
        'Gedachten om naar terug te keren.',
        action: FilledButton.icon(
          onPressed: () => editEntry(context, widget.app, 'note'),
          icon: const Icon(Icons.add),
          label: const Text('Nieuwe notitie'),
        ),
      ),
      TextField(
        decoration: const InputDecoration(
          labelText: 'Zoek in notities, passages en koppelingen',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: search,
      ),
      const SizedBox(height: 20),
      if (notes.isEmpty)
        const EmptyState(
          'Geen notities gevonden',
          'Maak een nieuwe notitie of probeer een andere zoekterm.',
        ),
      for (final note in notes) NoteCard(widget.app, note),
    ]);
  }
}

class TrackerPage extends StatelessWidget {
  const TrackerPage(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final covered = app.covered;
    return PageBody([
      const PageHeading(
        'Bijbeltracker',
        'Elk boek een stukje van het verhaal.',
      ),
      const Notice(
        'Een vers telt mee zodra er een notitie aan gekoppeld is. Schuif een hoofdstukrij horizontaal om alle hoofdstukken te zien.',
      ),
      for (final book in app.bible.books(
        app.repository!.scheme,
        extra: app.repository!.extra,
      ))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: () => openBook(context, app, book, 1),
                  child: Text(
                    book.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 58,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: book.chapters.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) => ChapterButton(
                      number: i + 1,
                      value:
                          (covered['${book.code}:${i + 1}']?.length ?? 0) /
                          book.chapters[i],
                      label:
                          '${book.name} ${i + 1}: ${covered['${book.code}:${i + 1}']?.length ?? 0} van ${book.chapters[i]} verzen met notities',
                      onTap: () => openBook(context, app, book, i + 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ]);
  }
}

class ChapterButton extends StatelessWidget {
  const ChapterButton({
    super.key,
    required this.number,
    required this.value,
    required this.label,
    required this.onTap,
  });
  final int number;
  final double value;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: const Color(0xFFF2F3EC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFCED6C6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: value.clamp(0, 1),
                    widthFactor: 1,
                    child: ColoredBox(
                      color: value >= 1 ? sage : const Color(0xFFB0BF9D),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: value >= 1 ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void openBook(
  BuildContext context,
  AppController app,
  Book book,
  int chapter,
) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => BookPage(app, book, chapter)),
);

class BookPage extends StatefulWidget {
  const BookPage(this.app, this.book, this.chapter, {super.key});
  final AppController app;
  final Book book;
  final int chapter;
  @override
  State<BookPage> createState() => _BookPageState();
}

class _BookPageState extends State<BookPage> {
  late int chapter = widget.chapter;
  int? verse;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final app = widget.app, book = widget.book;
      final covered = app.covered['${book.code}:$chapter'] ?? {};
      final notes = app
          .ofKind('note')
          .where(
            (n) => n.passages.any(
              (p) =>
                  p.book == book.code &&
                  p.chapter == chapter &&
                  (verse == null || p.start <= verse! && p.end >= verse!),
            ),
          )
          .toList();
      final reference =
          '${book.name} $chapter${verse == null ? '' : ':$verse'}';
      return Scaffold(
        appBar: AppBar(title: Text(reference)),
        body: PageBody([
          Row(
            children: [
              IconButton(
                tooltip: 'Vorig hoofdstuk',
                onPressed: chapter > 1
                    ? () => setState(() {
                        chapter--;
                        verse = null;
                      })
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: chapter,
                  items: [
                    for (var i = 1; i <= book.chapters.length; i++)
                      DropdownMenuItem(value: i, child: Text('Hoofdstuk $i')),
                  ],
                  onChanged: (v) => setState(() {
                    chapter = v!;
                    verse = null;
                  }),
                ),
              ),
              IconButton(
                tooltip: 'Volgend hoofdstuk',
                onPressed: chapter < book.chapters.length
                    ? () => setState(() {
                        chapter++;
                        verse = null;
                      })
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Tik op een vers om bijbehorende notities te zien.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: [
              for (var v = 1; v <= book.chapters[chapter - 1]; v++)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilterChip(
                    label: Text('$v'),
                    selected: verse == v,
                    backgroundColor: covered.contains(v)
                        ? const Color(0xFFCBD8BE)
                        : null,
                    onSelected: (_) =>
                        setState(() => verse = verse == v ? null : v),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => editEntry(
              context,
              app,
              'note',
              initial: {'references': reference},
            ),
            icon: const Icon(Icons.add),
            label: Text('Notitie bij $reference'),
          ),
          const SizedBox(height: 24),
          if (notes.isEmpty)
            const EmptyState(
              'Nog geen gedachten bij deze passage',
              'Lees in je Bijbel en bewaar hier wat je opvalt.',
            ),
          for (final n in notes) NoteCard(app, n),
        ]),
      );
    },
  );
}

class CollectionPage extends StatelessWidget {
  const CollectionPage(this.app, this.kind, {super.key});
  final AppController app;
  final String kind;
  @override
  Widget build(BuildContext context) {
    final label = const {
      'plan': 'Leesplannen',
      'study': 'Bijbelstudies',
      'theme': 'Thema’s',
      'group': 'Groepen',
    }[kind]!;
    return PageBody([
      PageHeading(
        label,
        'Verbind je gedachten en ontdek wat groeit.',
        action: FilledButton.icon(
          onPressed: () => editEntry(context, app, kind),
          icon: const Icon(Icons.add),
          label: const Text('Nieuw toevoegen'),
        ),
      ),
      if (kind == 'study') ...[
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AnimatedBuilder(
                animation: app,
                builder: (context, _) => Scaffold(
                  appBar: AppBar(title: const Text('Groepen')),
                  body: CollectionPage(app, 'group'),
                ),
              ),
            ),
          ),
          icon: const Icon(Icons.group_outlined),
          label: const Text('Groepen beheren'),
        ),
        const SizedBox(height: 20),
      ],
      if (app.ofKind(kind).isEmpty)
        const EmptyState(
          'Hier is nog ruimte.',
          'Voeg je eerste onderdeel toe. Je kunt er vervolgens notities aan koppelen.',
        ),
      for (final e in app.ofKind(kind))
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(20),
            title: Text(
              e.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              kind == 'plan'
                  ? '${e.sessions.length} sessies'
                  : kind == 'study'
                  ? '${e.text('date')} · ${e.text('kind') == 'solo' ? 'Alleen' : 'Met een groep'}'
                  : e.text('description'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openDetail(context, app, e.id),
          ),
        ),
    ]);
  }
}

void openDetail(BuildContext context, AppController app, String id) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => EntryPage(app, id)),
    );

class EntryPage extends StatelessWidget {
  const EntryPage(this.app, this.id, {super.key});
  final AppController app;
  final String id;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final e = app.entries.where((e) => e.id == id).firstOrNull;
      if (e == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const PageBody([
            EmptyState(
              'Dit onderdeel is niet beschikbaar.',
              'Het is verwijderd of heeft een conflict. Bekijk Instellingen voor herstel.',
            ),
          ]),
        );
      }
      final relation = const {
        'theme': 'themes',
        'plan': 'plans',
        'study': 'studies',
      }[e.kind];
      final related = relation == null
          ? <Entry>[]
          : app
                .ofKind('note')
                .where((n) => n.links(relation).contains(e.id))
                .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            e.kind == 'note' ? 'Een gedachte om te bewaren' : e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Bewerken',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => editEntry(context, app, e.kind, original: e),
            ),
            IconButton(
              tooltip: 'Versiegeschiedenis',
              icon: const Icon(Icons.history),
              onPressed: () => showHistory(context, app, e),
            ),
            IconButton(
              tooltip: 'Verwijderen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Naar de prullenbak?',
                  'Je kunt dit onderdeel later terugzetten via Instellingen.',
                  action: 'Verwijderen',
                )) {
                  try {
                    await app.save(
                      e.kind,
                      copyData(e),
                      original: e,
                      deleted: true,
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(describeError(error))),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
        body: PageBody([
          Text(e.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(shortDate(e.updated), style: const TextStyle(color: sage)),
          const SizedBox(height: 24),
          if (e.kind == 'note') ...[
            SelectableText(
              e.text('body'),
              style: const TextStyle(fontSize: 18, height: 1.75),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final passage in e.passages)
                  ActionChip(
                    label: Text(
                      app.bible.label(passage, app.repository!.scheme),
                    ),
                    onPressed: () => openBook(
                      context,
                      app,
                      app.bible.book(passage.book, app.repository!.scheme),
                      passage.chapter,
                    ),
                  ),
                for (final key in ['themes', 'plans', 'studies'])
                  for (final linked in app.entries.where(
                    (n) => e.links(key).contains(n.id),
                  ))
                    ActionChip(
                      label: Text(linked.title),
                      onPressed: () => openDetail(context, app, linked.id),
                    ),
              ],
            ),
          ],
          if (e.text('description').isNotEmpty)
            SelectableText(
              e.text('description'),
              style: const TextStyle(height: 1.6),
            ),
          if (e.kind == 'study')
            Text(
              '${e.text('date')} · ${e.text('kind') == 'solo' ? 'Alleen' : app.ofKind('group').where((g) => g.id == e.data['group']).firstOrNull?.title ?? 'Groep'}',
            ),
          if (e.kind == 'plan') ...[
            const SizedBox(height: 20),
            for (var i = 0; i < e.sessions.length; i++) _PlanSession(app, e, i),
          ],
          if (relation != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => editEntry(
                context,
                app,
                'note',
                initial: {
                  relation: [e.id],
                },
              ),
              icon: const Icon(Icons.add),
              label: const Text('Notitie toevoegen'),
            ),
            const SizedBox(height: 24),
            Text(
              'Bijbehorende gedachten',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (related.isEmpty)
              const Text('Nog geen notities aan dit onderdeel gekoppeld.'),
            for (final n in related) NoteCard(app, n),
          ],
        ]),
      );
    },
  );
}

class _PlanSession extends StatelessWidget {
  const _PlanSession(this.app, this.plan, this.number);
  final AppController app;
  final Entry plan;
  final int number;
  @override
  Widget build(BuildContext context) {
    final s = plan.sessions[number];
    final passages = (s['passages'] as List)
        .map((p) => Passage.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    final progress = passageProgress(passages, app.covered);
    return Card(
      child: ExpansionTile(
        leading: Icon(
          progress == 1 ? Icons.check_circle : Icons.circle_outlined,
          color: sage,
        ),
        title: Text(
          'Sessie ${number + 1}${(s['title'] as String).isEmpty ? '' : ' · ${s['title']}'}',
        ),
        subtitle: Text(s['references'] as String),
        childrenPadding: const EdgeInsets.all(20),
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 16),
          SelectableText(
            s['reflection'] as String,
            style: const TextStyle(height: 1.6),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => editEntry(
              context,
              app,
              'note',
              initial: {
                'references': s['references'],
                'plans': [plan.id],
              },
            ),
            icon: const Icon(Icons.edit_note),
            label: const Text('Schrijf je gedachten'),
          ),
        ],
      ),
    );
  }
}

Future<void> showHistory(
  BuildContext context,
  AppController app,
  Entry entry,
) async {
  final versions =
      app.repository!.history
          .where((r) => r.id == entry.id && !r.deleted)
          .toList()
        ..sort((a, b) => b.updated.compareTo(a.updated));
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Eerdere versies'),
      content: SizedBox(
        width: 600,
        height: 420,
        child: ListView(
          children: [
            for (final v in versions)
              ListTile(
                title: Text(
                  '${shortDate(v.updated)} · ${v.updated.toLocal().toString().substring(11, 16)}',
                ),
                subtitle: Text(
                  v.kind == 'note' ? v.text('body') : v.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: v.revision == entry.revision
                      ? null
                      : () async {
                          if (!await confirm(
                            context,
                            'Deze versie terugzetten?',
                            'De huidige versie blijft in de geschiedenis bewaard.',
                            action: 'Terugzetten',
                          )) {
                            return;
                          }
                          try {
                            await app.save(
                              v.kind,
                              copyData(v),
                              original: entry,
                            );
                            if (context.mounted) Navigator.pop(context);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(describeError(error))),
                              );
                            }
                          }
                        },
                  child: const Text('Terugzetten'),
                ),
              ),
          ],
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
}

class SettingsPage extends StatelessWidget {
  const SettingsPage(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final repo = app.repository!;
    final prefs = repo.ofKind('preferences').firstOrNull;
    final deleted = repo.heads.values
        .where((v) => v.length == 1 && v.first.deleted)
        .map((v) => v.first)
        .toList();
    return PageBody([
      const PageHeading(
        'Jouw studieboek',
        'Je gegevens blijven op de plek die jij kiest.',
      ),
      if (app.notice != null) Notice(app.notice!),
      SyncPanel(app),
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(repo.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              SelectableText(
                kIsWeb
                    ? 'Op dit apparaat, in deze browser'
                    : repo.files.location.kind == 'path'
                    ? repo.files.location.token
                    : repo.files.location.label,
              ),
              const SizedBox(height: 10),
              const Text(
                kIsWeb
                    ? 'Alle notities en eerdere versies staan in deze browser. Bewaar regelmatig een reservekopie buiten de browser. De inhoud is niet versleuteld.'
                    : 'Deze map bevat alle notities en eerdere versies. Maak regelmatig een kopie van de volledige map. De inhoud is niet versleuteld.',
              ),
              const SizedBox(height: 16),
              if (kIsWeb)
                OutlinedButton.icon(
                  onPressed: app.busy ? null : () => app.run(app.exportBackup),
                  icon: const Icon(Icons.download),
                  label: const Text('Reservekopie downloaden'),
                ),
              OutlinedButton.icon(
                onPressed: () => app.run(() async {
                  await app.closeBook();
                }),
                icon: const Icon(Icons.folder_open),
                label: const Text('Ander studieboek openen'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(
        key: ValueKey(repo.scheme),
        initialValue: repo.scheme,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Hoofdstuk- en versindeling',
        ),
        items: const [
          DropdownMenuItem(value: 'english', child: Text('Paratext English')),
          DropdownMenuItem(
            value: 'original',
            child: Text('Hebreeuws / BHS (Oude Testament)'),
          ),
        ],
        onChanged: repo.hasPassages || (repo.heads[repo.id]?.length ?? 0) > 1
            ? null
            : (value) => app.run(() async {
                await app.save(
                  'preferences',
                  {'versification': value, 'deuterocanonical': repo.extra},
                  original: prefs,
                  id: repo.id,
                );
              }),
      ),
      if (repo.hasPassages)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'De versindeling staat vast omdat er passages zijn opgeslagen.',
          ),
        ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Deuterocanonieke boeken tonen'),
        value: repo.extra,
        onChanged: (repo.heads[repo.id]?.length ?? 0) > 1
            ? null
            : (value) => app.run(() async {
                await app.save(
                  'preferences',
                  {'versification': repo.scheme, 'deuterocanonical': value},
                  original: prefs,
                  id: repo.id,
                );
              }),
      ),
      const SizedBox(height: 20),
      Text(
        'Herstel en geschiedenis',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      for (final warning in repo.warnings) Notice(warning, error: true),
      for (final conflict in repo.conflicts)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Twee versies van hetzelfde onderdeel',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Bekijk beide versies en kies welke je wilt gebruiken. Alle eerdere bestanden blijven bewaard.',
                ),
                for (final version in conflict)
                  ListTile(
                    title: Text(
                      version.deleted ? 'Verwijderde versie' : version.title,
                    ),
                    subtitle: SelectableText(
                      version.kind == 'note'
                          ? version.text('body')
                          : '${version.data}',
                    ),
                    trailing: TextButton(
                      child: const Text('Gebruik'),
                      onPressed: () => app.run(() async {
                        await app.save(
                          version.kind,
                          copyData(version),
                          id: version.id,
                          parents: conflict.map((e) => e.revision).toList(),
                          deleted: version.deleted,
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      Text(
        'Prullenbak (${deleted.length})',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (deleted.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Er zijn geen verwijderde onderdelen.'),
        ),
      for (final e in deleted)
        ListTile(
          title: Text(e.title),
          subtitle: Text(shortDate(e.updated)),
          trailing: TextButton(
            onPressed: () => app.run(() async {
              await app.save(e.kind, copyData(e), original: e);
            }),
            child: const Text('Terugzetten'),
          ),
        ),
      const SizedBox(height: 24),
      const Notice(
        'Controleer de laatste synchronisatie voordat je op een ander apparaat verdergaat. Bij gelijktijdige wijzigingen blijven beide versies bewaard bij Herstel en geschiedenis.',
      ),
      TextButton(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'Mosterdzaad',
          applicationVersion: '0.2.0',
        ),
        child: const Text('Over Mosterdzaad en licenties'),
      ),
    ]);
  }
}
