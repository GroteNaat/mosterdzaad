import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:loro_crdt/loro_crdt.dart';

import 'entry.dart';
import '../sync/canonical.dart';

/// The tested Loro engine owns sequence ordering, causality and convergence.
/// Immutable record files are also the durable local operation log. No clock
/// participates in conflict resolution. A fresh peer per edit allows a stale
/// editor to fork its original causal state without reusing actor counters.
class CollaborativeEntry {
  CollaborativeEntry(this.records);
  final List<Entry> records; // Topologically sorted, one entity only.
  final _updates = <String, Uint8List>{};
  static const textFields = {'body', 'description'};
  static const setFields = {'themes', 'plans', 'studies', 'planSessions'};

  static String peer(String revision) => BigInt.parse(
    sha256
        .convert(utf8.encode('mosterdzaad/loro/$revision'))
        .toString()
        .substring(0, 16),
    radix: 16,
  ).toString();

  Set<String> ancestors(Iterable<String> heads) {
    final byId = {for (final e in records) e.revision: e};
    final found = <String>{}, pending = heads.toList();
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!found.add(id)) continue;
      final entry = byId[id];
      if (entry == null) {
        throw const FormatException('Een causale voorganger ontbreekt.');
      }
      pending.addAll(entry.parents);
    }
    return found;
  }

  LoroDoc document(Iterable<String> heads) {
    final included = ancestors(heads);
    final doc = LoroDoc();
    try {
      for (final entry in records) {
        if (!included.contains(entry.revision)) continue;
        doc.import(
          _updates.putIfAbsent(entry.revision, () {
            if (entry.crdt != null) {
              final bytes = base64Decode(entry.crdt!);
              LoroDoc.decodeImportBlobMeta(bytes, checkChecksum: true);
              return bytes;
            }
            // Deterministic, read-only migration of v1 history. All replicas
            // derive identical actors and operations; old files stay untouched.
            return edit(entry.revision, entry.parents, entry.data);
          }),
        );
      }
      return doc;
    } catch (_) {
      doc.dispose();
      rethrow;
    }
  }

  Uint8List edit(
    String revision,
    List<String> parents,
    Map<String, dynamic> data,
  ) {
    final doc = document(parents)..peerId = peer(revision);
    try {
      final before = doc.oplogVersion;
      final metadata = doc.getMap('metadata');
      for (final field in data.keys) {
        final value = data[field];
        if (textFields.contains(field)) {
          doc.getText(field).update(value as String);
        } else if (setFields.contains(field)) {
          final set = doc.getMap('set_$field');
          final desired = (value as List).cast<String>().toSet();
          final existing = set.entries;
          for (final item in existing.entries) {
            if (!desired.contains(item.value)) set.delete(item.key);
          }
          for (final item in desired.difference(
            existing.values.cast<String>().toSet(),
          )) {
            // Observed-remove set: a concurrent re-add has its own tag.
            set['$revision/$item'] = item;
          }
        } else if (field == 'references' || field == 'passages') {
          // Text and parsed references must change together.
          if (field == 'passages') continue;
          final reference = {'references': value, 'passages': data['passages']};
          if (canonicalJson(metadata['reference']) !=
              canonicalJson(reference)) {
            metadata['reference'] = reference;
          }
        } else if (canonicalJson(metadata[field]) != canonicalJson(value)) {
          metadata[field] = value;
        }
      }
      doc.commit(timestamp: 0);
      return doc.exportUpdates(from: before);
    } finally {
      doc.dispose();
    }
  }

  Entry project(List<Entry> heads) {
    final sorted = heads.toList()
      ..sort((a, b) => a.revision.compareTo(b.revision));
    final doc = document(sorted.map((e) => e.revision));
    try {
      final data = Map<String, dynamic>.from(doc.getMap('metadata').entries);
      final reference = data.remove('reference');
      if (reference is Map) data.addAll(Map<String, dynamic>.from(reference));
      final fields = records.expand((e) => e.data.keys).toSet();
      for (final field in fields.intersection(textFields)) {
        data[field] = doc.getText(field).toString();
      }
      for (final field in fields.intersection(setFields)) {
        data[field] =
            doc
                .getMap('set_$field')
                .entries
                .values
                .cast<String>()
                .toSet()
                .toList()
              ..sort();
      }
      final selected = sorted.first;
      final created = records.where((e) => e.parents.isEmpty).toList()
        ..sort((a, b) => a.revision.compareTo(b.revision));
      return Entry(
        id: selected.id,
        revision: selected.revision,
        parents: selected.parents,
        kind: selected.kind,
        data: data,
        updated: heads
            .map((e) => e.updated)
            .reduce((a, b) => a.isAfter(b) ? a : b),
        created: created.first.created ?? created.first.updated,
        // Delete wins over a concurrent edit. The merged text stays in trash;
        // restoring observes all heads and is an explicit new operation.
        deleted: heads.any((e) => e.deleted),
        causalHeads: sorted.map((e) => e.revision).toList(),
        causalHashes: {
          for (final e in heads)
            if (e.fileFingerprint != null) e.revision: e.fileFingerprint!,
        },
      );
    } finally {
      doc.dispose();
    }
  }

  /// Multi-value view of concurrent metadata writes. Loro's deterministic
  /// register supplies the displayed value; all alternatives remain visible
  /// until an explicit write observes and resolves them. Text and tag sets are
  /// merged by Loro and never replaced by a metadata-choice action.
  List<List<Entry>> conflicts(List<Entry> heads, Entry projected) {
    final writers = <String, List<Entry>>{};
    for (final entry in records) {
      final base = document(entry.parents);
      try {
        final metadata = base.getMap('metadata');
        for (final field in entry.data.keys) {
          if (textFields.contains(field) ||
              setFields.contains(field) ||
              field == 'passages') {
            continue;
          }
          final value = field == 'references'
              ? {
                  'references': entry.data[field],
                  'passages': entry.data['passages'],
                }
              : entry.data[field];
          final previous =
              metadata[field == 'references' ? 'reference' : field];
          if (canonicalJson(previous) != canonicalJson(value)) {
            (writers[field] ??= []).add(entry);
          }
        }
      } finally {
        base.dispose();
      }
    }
    final result = <List<Entry>>[];
    for (final pair in writers.entries) {
      final superseded = pair.value.expand((e) => ancestors(e.parents)).toSet();
      final concurrent = pair.value
          .where((e) => !superseded.contains(e.revision))
          .toList();
      final distinct = <String, Entry>{
        for (final e in concurrent) canonicalJson(e.data[pair.key]): e,
      };
      if (distinct.length < 2) continue;
      result.add([
        for (final choice in distinct.values)
          Entry(
            id: projected.id,
            revision: choice.revision,
            parents: choice.parents,
            kind: projected.kind,
            data: {
              ...projected.data,
              pair.key: choice.data[pair.key],
              if (pair.key == 'references') 'passages': choice.data['passages'],
            },
            updated: choice.updated,
            deleted: projected.deleted,
            created: projected.created,
            causalHeads: projected.causalHeads,
            causalHashes: projected.causalHashes,
            conflictField: pair.key,
          ),
      ]);
    }
    return result;
  }
}
