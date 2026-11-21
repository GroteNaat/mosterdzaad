import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../app_controller.dart';
import '../domain/entry.dart';
import '../domain/plan_progress.dart';
import 'common.dart';

Future<void> editEntry(
  BuildContext context,
  AppController app,
  String kind, {
  Entry? original,
  Map<String, dynamic>? initial,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        EntryEditor(app, kind, original: original, initial: initial),
  ),
);

class EntryEditor extends StatefulWidget {
  const EntryEditor(
    this.app,
    this.kind, {
    super.key,
    this.original,
    this.initial,
  });
  final AppController app;
  final String kind;
  final Entry? original;
  final Map<String, dynamic>? initial;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _SessionFields {
  _SessionFields(Map<String, dynamic> data)
    : id = data['id'] as String? ?? const Uuid().v4(),
      title = TextEditingController(text: data['title'] as String? ?? ''),
      references = TextEditingController(
        text: data['references'] as String? ?? '',
      ),
      reflection = TextEditingController(
        text: data['reflection'] as String? ?? '',
      );
  final TextEditingController title, references, reflection;
  final String id;
  void dispose() {
    title.dispose();
    references.dispose();
    reflection.dispose();
  }
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final links = <String, Set<String>>{};
  final sessions = <_SessionFields>[];
  final sessionCount = TextEditingController();
  List<String> planSessions = [];
  int get activeSessionCount => int.tryParse(sessionCount.text) ?? 0;
  late String studyKind;
  String? group, error;
  bool saving = false, dirty = false, allowPop = false;
  late final AppLifecycleListener lifecycle;
  late final Future<bool> Function() navigationGuard;
  AppController get app => widget.app;
  String get kind => widget.kind;
  String get label => const {
    'note': 'notitie',
    'plan': 'leesplan',
    'study': 'bijbelstudie',
    'theme': 'thema',
    'group': 'groep',
  }[kind]!;
  TextEditingController field(String key) => fields[key]!;
  @override
  void initState() {
    super.initState();
    final data = widget.original?.data ?? widget.initial ?? {};
    for (final key in [
      'title',
      'body',
      'references',
      'description',
      'name',
      'date',
    ]) {
      fields[key] = TextEditingController(
        text:
            data[key] as String? ??
            (key == 'date'
                ? DateTime.now().toIso8601String().substring(0, 10)
                : ''),
      )..addListener(changed);
    }
    for (final key in ['themes', 'plans', 'studies']) {
      links[key] = Set<String>.from(data[key] as List? ?? []);
    }
    studyKind = data['kind'] as String? ?? 'solo';
    group = data['group'] as String?;
    planSessions = List<String>.from(data['planSessions'] as List? ?? []);
    final initialSessions = data['sessions'] as List? ?? [];
    for (var i = 0; i < initialSessions.length; i++) {
      addSession({
        ...Map<String, dynamic>.from(initialSessions[i] as Map),
        if (widget.original != null) 'id': sessionId(widget.original!, i),
      });
    }
    if (sessions.isNotEmpty) sessionCount.text = '${sessions.length}';
    navigationGuard = () async => allowPop || (!saving && await mayLeave());
    app.beforeNavigation = navigationGuard;
    lifecycle = AppLifecycleListener(
      onExitRequested: () async => saving
          ? AppExitResponse.cancel
          : await mayLeave()
          ? AppExitResponse.exit
          : AppExitResponse.cancel,
    );
  }

  void changed() {
    if (!dirty && mounted) setState(() => dirty = true);
  }

  void addSession(Map<String, dynamic> data) {
    final s = _SessionFields(data);
    for (final c in [s.title, s.references, s.reflection]) {
      c.addListener(changed);
    }
    sessions.add(s);
  }

  @override
  void dispose() {
    if (identical(app.beforeNavigation, navigationGuard)) {
      app.beforeNavigation = null;
    }
    lifecycle.dispose();
    sessionCount.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    for (final s in sessions) {
      s.dispose();
    }
    super.dispose();
  }

  Future<bool> mayLeave() async =>
      !dirty ||
      await confirm(
        context,
        'Wijzigingen nog niet opgeslagen',
        'Wil je dit venster sluiten en je wijzigingen laten vervallen?',
        action: 'Wijzigingen laten vervallen',
      );

  Widget input(
    String key,
    String label, {
    bool required = false,
    int lines = 1,
    int? max,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: field(key),
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 8,
      maxLength: max,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: required
          ? (v) => v == null || v.trim().isEmpty ? 'Vul dit veld in.' : null
          : null,
    ),
  );
  List<Map<String, dynamic>> parse(String text) => app.bible
      .parse(text, app.repository!.scheme)
      .map((p) => p.toJson())
      .toList();

  Map<String, dynamic> values() {
    final data = <String, dynamic>{};
    switch (kind) {
      case 'note':
        data.addAll({
          'title': field('title').text.trim(),
          'body': field('body').text,
          'references': field('references').text.trim(),
          'passages': parse(field('references').text),
          for (final e in links.entries) e.key: e.value.toList(),
          if (planSessions.isNotEmpty)
            'planSessions': planSessions
                .where((s) => links['plans']!.contains(s.split('/').first))
                .toList(),
        });
      case 'plan':
        data.addAll({
          'title': field('title').text.trim(),
          'description': field('description').text,
          'sessions': sessions
              .take(activeSessionCount)
              .map(
                (s) => {
                  'id': s.id,
                  'title': s.title.text.trim(),
                  'references': s.references.text.trim(),
                  'reflection': s.reflection.text,
                  'passages': parse(s.references.text),
                },
              )
              .toList(),
        });
      case 'study':
        data.addAll({
          'title': field('title').text.trim(),
          'date': field('date').text,
          'kind': studyKind,
          'group': studyKind == 'solo' ? null : group,
        });
      case 'theme':
        data.addAll({
          'name': field('name').text.trim(),
          'description': field('description').text,
        });
      case 'group':
        data['name'] = field('name').text.trim();
    }
    return data;
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (kind == 'plan' &&
        activeSessionCount < sessions.length &&
        sessions
            .skip(activeSessionCount)
            .any(
              (s) =>
                  s.title.text.isNotEmpty ||
                  s.references.text.isNotEmpty ||
                  s.reflection.text.isNotEmpty ||
                  (widget.original?.sessions.length ?? 0) > activeSessionCount,
            )) {
      if (!await confirm(
            context,
            'Leesplan inkorten?',
            'De sessies na nummer $activeSessionCount worden uit het leesplan verwijderd. Je bestaande notities blijven behouden.',
            action: 'Inkorten en opslaan',
          ) ||
          !mounted) {
        return;
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await app.save(kind, values(), original: widget.original);
      if (mounted) {
        setState(() {
          dirty = false;
          allowPop = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = describeError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop || (!dirty && !saving),
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || saving) return;
      if (await mayLeave() && mounted) {
        setState(() => allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (context.mounted) Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.original == null ? (['plan', 'theme'].contains(kind) ? 'Nieuw' : 'Nieuwe') : 'Bewerk'} $label',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.check),
              label: Text(saving ? 'Bewaren…' : 'Opslaan'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (error != null) Notice(error!, error: true),
                  if (saving) const LinearProgressIndicator(),
                  if (kind == 'note') ...[
                    input('title', 'Titel (optioneel)', max: 160),
                    input(
                      'body',
                      'Wat wil je bewaren?',
                      required: true,
                      lines: 9,
                      hint: 'Wat valt je op? Wat neem je mee?',
                    ),
                    input(
                      'references',
                      'Bijbelverwijzingen',
                      lines: 2,
                      hint: 'Johannes 3:16–18; Psalm 23',
                    ),
                    const Text(
                      'Hele hoofdstukken en bereiken zoals Genesis 1–3 zijn ook mogelijk. Verzen met een notitie vullen de tracker.',
                    ),
                    const SizedBox(height: 20),
                    for (final item in const [
                      ('themes', 'theme', 'Thema’s'),
                      ('plans', 'plan', 'Leesplannen'),
                      ('studies', 'study', 'Bijbelstudies'),
                    ]) ...[
                      Text(
                        item.$3,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (app.ofKind(item.$2).isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Nog geen onderdelen. Je kunt ze later toevoegen.',
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in app.ofKind(item.$2))
                            FilterChip(
                              label: Text(e.title),
                              selected: links[item.$1]!.contains(e.id),
                              onSelected: (v) => setState(() {
                                v
                                    ? links[item.$1]!.add(e.id)
                                    : links[item.$1]!.remove(e.id);
                                dirty = true;
                              }),
                            ),
                          for (final id in links[item.$1]!.where(
                            (id) => !app.ofKind(item.$2).any((e) => e.id == id),
                          ))
                            InputChip(
                              label: const Text('Verwijderde koppeling'),
                              onDeleted: () => setState(() {
                                links[item.$1]!.remove(id);
                                dirty = true;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                    ],
                  ],
                  if (kind == 'theme' || kind == 'group')
                    input('name', 'Naam', required: true, max: 100),
                  if (kind == 'study' || kind == 'plan')
                    input('title', 'Titel', required: true, max: 160),
                  if (kind == 'theme' || kind == 'plan')
                    input('description', 'Omschrijving', lines: 3),
                  if (kind == 'study') ...[
                    TextFormField(
                      controller: field('date'),
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Datum',
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate:
                              DateTime.tryParse(field('date').text) ??
                              DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2200),
                        );
                        if (selected != null) {
                          field('date').text = selected
                              .toIso8601String()
                              .substring(0, 10);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'solo', label: Text('Alleen')),
                        ButtonSegment(
                          value: 'group',
                          label: Text('Met een groep'),
                        ),
                      ],
                      selected: {studyKind},
                      onSelectionChanged: (v) => setState(() {
                        studyKind = v.first;
                        dirty = true;
                      }),
                    ),
                    if (studyKind == 'group') ...[
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue:
                            app.ofKind('group').any((e) => e.id == group)
                            ? group
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Groep'),
                        items: app
                            .ofKind('group')
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(e.title),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          group = v;
                          dirty = true;
                        }),
                        validator: (v) => v == null
                            ? 'Maak eerst een groep aan bij Bijbelstudies.'
                            : null,
                      ),
                    ],
                  ],
                  if (kind == 'plan') ...[
                    TextFormField(
                      controller: sessionCount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Aantal dagen / sessies',
                        hintText: 'Bijvoorbeeld 10',
                        helperText:
                            'Kies 1 tot 366. Je kunt dit later aanpassen.',
                      ),
                      validator: (value) {
                        final count = int.tryParse(value ?? '');
                        return count == null || count < 1 || count > 366
                            ? 'Vul een aantal van 1 tot 366 in.'
                            : null;
                      },
                      onChanged: (value) {
                        final count = int.tryParse(value);
                        setState(() {
                          dirty = true;
                          if (count != null && count >= 1 && count <= 366) {
                            while (sessions.length < count) {
                              addSession({});
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 22),
                    for (
                      var i = 0;
                      i < activeSessionCount.clamp(0, sessions.length);
                      i++
                    )
                      Card(
                        child: ExpansionTile(
                          key: ObjectKey(sessions[i]),
                          title: Text(
                            'Sessie ${i + 1}${sessions[i].title.text.isEmpty ? '' : ' · ${sessions[i].title.text}'}',
                          ),
                          childrenPadding: const EdgeInsets.all(16),
                          children: [
                            TextFormField(
                              controller: sessions[i].title,
                              maxLength: 160,
                              decoration: const InputDecoration(
                                labelText: 'Titel (optioneel)',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: sessions[i].references,
                              minLines: 2,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: 'Bijbelverwijzingen',
                                hintText: 'Psalm 23',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: sessions[i].reflection,
                              minLines: 4,
                              maxLines: 12,
                              decoration: const InputDecoration(
                                labelText: 'Overdenking en vragen',
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (activeSessionCount > 1)
                              TextButton.icon(
                                icon: const Icon(Icons.remove_circle_outline),
                                label: const Text('Sessie verwijderen'),
                                onPressed: () async {
                                  if (await confirm(
                                        context,
                                        'Sessie verwijderen?',
                                        'De sessie wordt verwijderd wanneer je het leesplan opslaat.',
                                        action: 'Verwijderen',
                                      ) &&
                                      mounted) {
                                    setState(() {
                                      final removed = sessions.removeAt(i);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => removed.dispose(),
                                          );
                                      sessionCount.text =
                                          (activeSessionCount - 1).toString();
                                      dirty = true;
                                    });
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: activeSessionCount >= 366
                          ? null
                          : () => setState(() {
                              final next = activeSessionCount + 1;
                              if (sessions.length < next) addSession({});
                              sessionCount.text = next.toString();
                              dirty = true;
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('Sessie toevoegen'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    dirty ? 'Er zijn nog niet opgeslagen wijzigingen.' : 'Je wijzigingen worden bij Opslaan in je lokale studieboek bewaard.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: const Text('Opslaan in studieboek'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Map<String, dynamic> copyData(Entry e) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(e.data)) as Map);
