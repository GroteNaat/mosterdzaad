import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bible.dart';

const entryKinds = [
  'note',
  'plan',
  'study',
  'theme',
  'group',
  'preferences',
  'purge',
];
final uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

class Entry {
  Entry({
    required this.id,
    required this.revision,
    required this.parents,
    required this.kind,
    required this.data,
    required this.updated,
    this.deleted = false,
    this.fileFingerprint,
    this.crdt,
    this.actor,
    this.created,
    this.causalHeads,
    this.causalHashes,
    this.conflictField,
  });
  final String id, revision, kind;
  final List<String> parents;
  final Map<String, dynamic> data;
  final DateTime updated;
  final bool deleted;
  final String? fileFingerprint;
  final String? crdt, actor;
  final DateTime? created;
  final List<String>? causalHeads;
  final Map<String, String>? causalHashes;
  final String? conflictField;
  String text(String key) => data[key] as String? ?? '';
  List<String> links(String key) => List<String>.from(data[key] as List? ?? []);
  List<Passage> get passages => (data['passages'] as List? ?? [])
      .map((p) => Passage.fromJson(Map<String, dynamic>.from(p as Map)))
      .toList();
  String get title => text('title').isNotEmpty
      ? text('title')
      : text('name').isNotEmpty
      ? text('name')
      : text('body').split('\n').first;
  List<Map<String, dynamic>> get sessions => (data['sessions'] as List? ?? [])
      .map((s) => Map<String, dynamic>.from(s as Map))
      .toList();
  Map<String, dynamic> toJson() => {
    'format': 'mosterdzaad-record',
    'version': crdt == null ? 1 : 2,
    if (crdt != null) 'crdt': crdt,
    if (actor != null) 'actor': actor,
    if (created != null) 'created': created!.toUtc().toIso8601String(),
    'id': id,
    'revision': revision,
    'parents': parents,
    'kind': kind,
    'updated': updated.toUtc().toIso8601String(),
    'deleted': deleted,
    'data': data,
  };
  String get filename => '$revision.${kind == 'note' ? 'md' : 'json'}';

  String encode() {
    final j = toJson();
    if (kind != 'note') return '${jsonEncode(j)}\n';
    j['data'] = {...data}..remove('body');
    return '---\n${jsonEncode(j)}\n---\n${text('body')}\n<!-- mosterdzaad:end -->\n';
  }

  static Entry decode(String contents, String filename) {
    Map<String, dynamic> j;
    if (filename.endsWith('.md')) {
      const ending = '\n<!-- mosterdzaad:end -->\n';
      if (!contents.startsWith('---\n') || !contents.endsWith(ending)) {
        throw const FormatException('Onvolledig notitiebestand.');
      }
      final end = contents.indexOf('\n---\n', 4);
      if (end < 0) throw const FormatException('Metadata ontbreekt.');
      j = Map<String, dynamic>.from(
        jsonDecode(contents.substring(4, end)) as Map,
      );
      j['data'] = {
        ...Map<String, dynamic>.from(j['data'] as Map),
        'body': contents.substring(end + 5, contents.length - ending.length),
      };
    } else {
      j = Map<String, dynamic>.from(jsonDecode(contents) as Map);
    }
    if (j['format'] != 'mosterdzaad-record' || ![1, 2].contains(j['version'])) {
      throw const FormatException('Onbekend bestandsformaat.');
    }
    final entry = Entry(
      id: j['id'] as String,
      revision: j['revision'] as String,
      parents: List<String>.from(j['parents'] as List),
      kind: j['kind'] as String,
      data: Map<String, dynamic>.from(j['data'] as Map),
      updated: DateTime.parse(j['updated'] as String),
      deleted: j['deleted'] as bool,
      fileFingerprint: sha256.convert(utf8.encode(contents)).toString(),
      crdt: j['crdt'] as String?,
      actor: j['actor'] as String?,
      created: j['created'] == null
          ? null
          : DateTime.parse(j['created'] as String),
    );
    if (!uuidPattern.hasMatch(entry.id) ||
        !uuidPattern.hasMatch(entry.revision) ||
        entry.parents.any(
          (p) => !uuidPattern.hasMatch(p) || p == entry.revision,
        ) ||
        !entryKinds.contains(entry.kind) ||
        filename != entry.filename ||
        (j['version'] == 2 &&
            (entry.crdt == null ||
                entry.actor == null ||
                entry.created == null))) {
      throw const FormatException('Ongeldige record-identiteit.');
    }
    return entry;
  }
}

void validateData(
  String kind,
  Map<String, dynamic> data,
  Bible bible,
  String scheme,
) {
  String text(String key, {bool required = false, int max = 1000000}) {
    final v = data[key];
    if (v is! String || (required && v.trim().isEmpty) || v.length > max) {
      throw FormatException('Ongeldige waarde voor $key.');
    }
    return v;
  }

  void refs(dynamic value) {
    if (value is! List || value.length > 5000) {
      throw const FormatException('Ongeldige passages.');
    }
    for (final p in value) {
      bible.validate(
        Passage.fromJson(Map<String, dynamic>.from(p as Map)),
        scheme,
      );
    }
  }

  switch (kind) {
    case 'purge':
      validatePurge(data);
    case 'note':
      text('title', max: 160);
      text('body', required: true);
      text('references');
      refs(data['passages']);
      var linked = (data['passages'] as List).isNotEmpty;
      for (final key in ['themes', 'plans', 'studies']) {
        final v = data[key];
        if (v is! List ||
            v.any((id) => id is! String || !uuidPattern.hasMatch(id))) {
          throw FormatException('Ongeldige koppeling: $key.');
        }
        linked = linked || v.isNotEmpty;
      }
      if (!linked) {
        throw const FormatException(
          'Koppel je notitie aan een passage, thema, leesplan of studie.',
        );
      }
      if (data['planSessions'] != null &&
          (data['planSessions'] is! List ||
              (data['planSessions'] as List).any(
                (v) =>
                    v is! String ||
                    v.split('/').length != 2 ||
                    !v.split('/').every(uuidPattern.hasMatch),
              ))) {
        throw const FormatException('Ongeldige sessiekoppeling.');
      }
    case 'plan':
      text('title', required: true, max: 160);
      text('description');
      final sessions = data['sessions'];
      if (sessions is! List || sessions.isEmpty || sessions.length > 366) {
        throw const FormatException('Kies 1 tot 366 sessies.');
      }
      for (final s in sessions) {
        if (s is! Map ||
            s['title'] is! String ||
            s['reflection'] is! String ||
            s['references'] is! String) {
          throw const FormatException('Ongeldige sessie.');
        }
        refs(s['passages']);
        if (s['id'] != null &&
            (s['id'] is! String || !uuidPattern.hasMatch(s['id'] as String))) {
          throw const FormatException('Ongeldige sessie-ID.');
        }
      }
      final ids = sessions
          .where((s) => s['id'] != null)
          .map((s) => s['id'])
          .toList();
      if (ids.toSet().length != ids.length) {
        throw const FormatException('Dubbele sessie-ID.');
      }
    case 'study':
      text('title', required: true, max: 160);
      final date = text('date');
      final parsed = DateTime.tryParse(date);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
        throw const FormatException('Kies een geldige datum.');
      }
      if (!['solo', 'group'].contains(data['kind']) ||
          (data['kind'] == 'group' &&
              (data['group'] is! String ||
                  !uuidPattern.hasMatch(data['group'] as String))) ||
          (data['kind'] == 'solo' && data['group'] != null)) {
        throw const FormatException('Kies een groep of kies Alleen.');
      }
    case 'theme':
      text('name', required: true, max: 100);
      text('description');
    case 'group':
      text('name', required: true, max: 100);
    case 'preferences':
      if (!['english', 'original'].contains(data['versification']) ||
          data['deuterocanonical'] is! bool) {
        throw const FormatException('Ongeldige instellingen.');
      }
    default:
      throw const FormatException('Onbekend onderdeel.');
  }
}

/// A permanent deletion keeps only opaque identities and integrity hashes.
/// It always wins over an offline edit or restore of the same entity ID.
void validatePurge(Map<String, dynamic> data) {
  if (data['target'] is! String ||
      !uuidPattern.hasMatch(data['target'] as String) ||
      !['note', 'plan', 'study', 'theme', 'group'].contains(data['kind']) ||
      data['revisions'] is! Map ||
      (data['revisions'] as Map).isEmpty ||
      (data['revisions'] as Map).entries.any(
        (e) =>
            e.key is! String ||
            !uuidPattern.hasMatch(e.key as String) ||
            e.value is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(e.value as String),
      ) ||
      data.keys.any((k) => !['target', 'kind', 'revisions'].contains(k))) {
    throw const FormatException('Ongeldige definitieve verwijdering.');
  }
}

Set<String> purgedIds(Iterable<Entry> records) {
  final ids = <String>{};
  for (final e in records.where((e) => e.kind == 'purge')) {
    validatePurge(e.data);
    ids.add(e.data['target'] as String);
  }
  return ids;
}

Map<String, String> purgedRevisions(Iterable<Entry> records) => {
  for (final e in records.where((e) => e.kind == 'purge'))
    ...Map<String, String>.from(e.data['revisions'] as Map),
};

/// Leaves of the revision graph. Concurrent edits remain separate, never LWW.
Map<String, List<Entry>> revisionHeads(Iterable<Entry> entries) {
  final grouped = <String, List<Entry>>{};
  for (final e in entries) {
    grouped.putIfAbsent(e.id, () => []).add(e);
  }
  return grouped.map((id, versions) {
    final ancestors = versions.expand((e) => e.parents).toSet();
    return MapEntry(
      id,
      versions.where((e) => !ancestors.contains(e.revision)).toList()
        ..sort((a, b) => b.updated.compareTo(a.updated)),
    );
  });
}
