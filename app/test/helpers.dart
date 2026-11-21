import 'dart:io';

import 'package:mosterdzaad/domain/bible.dart';
import 'package:mosterdzaad/storage/vault_files.dart';

Bible testBible() => Bible(
  File('assets/data/books.json').readAsStringSync(),
  File('assets/data/books-original.json').readAsStringSync(),
);
Map<String, dynamic> noteData(
  Bible bible, {
  String body = 'Een gedachte',
  String references = 'Johannes 3:16–18',
}) => {
  'title': 'Hoop',
  'body': body,
  'references': references,
  'passages': bible
      .parse(references, 'english')
      .map((p) => p.toJson())
      .toList(),
  'themes': <String>[],
  'plans': <String>[],
  'studies': <String>[],
};

class MemoryFiles implements VaultFiles {
  final contents = <String, String>{};
  final directories = <String>{};
  bool failWrite = false, denied = false;
  int removals = 0;
  int? failRemoveAt;
  @override
  VaultLocation get location =>
      const VaultLocation('memory', 'memory', 'Mijn studieboek');
  @override
  Future<void> makeDirectory(String name) async {
    directories.add(name);
  }

  @override
  Future<List<String>> list(String directory) async {
    if (denied) throw const FileSystemException('Toegang ingetrokken');
    return contents.keys
        .where((p) => p.startsWith('$directory/'))
        .map((p) => p.substring(directory.length + 1))
        .toList();
  }

  @override
  Future<String?> read(String name) async {
    if (denied) throw const FileSystemException('Toegang ingetrokken');
    return contents[name];
  }

  @override
  Future<void> remove(String name) async {
    if (++removals == failRemoveAt) {
      throw const FileSystemException('Verwijderen onderbroken');
    }
    contents.remove(name);
  }

  @override
  Future<void> writeNew(String name, String text) async {
    if (failWrite) throw const FileSystemException('Schijf vol');
    if (contents.containsKey(name)) {
      throw const FileSystemException('Bestaat al');
    }
    contents[name] = text;
  }
}
