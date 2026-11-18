import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'vault_types.dart';

class LocalVaultFiles implements VaultFiles {
  LocalVaultFiles(this.location);
  @override
  final VaultLocation location;
  String path(String name) {
    checkRelative(name);
    return p.joinAll([location.token, ...name.split('/')]);
  }

  @override
  Future<List<String>> list(String directory) async {
    final dir = Directory(path(directory));
    if (!await dir.exists()) {
      throw FileSystemException('De map ontbreekt.', dir.path);
    }
    return dir
        .list(followLinks: false)
        .where((e) => e is File)
        .map((e) => p.basename(e.path))
        .toList();
  }

  @override
  Future<String?> read(String name) async {
    final file = File(path(name));
    if (!await file.exists()) return null;
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException(
        'Dit bestand is te groot voor een studieboekrecord.',
      );
    }
    return file.readAsString();
  }

  @override
  Future<void> writeNew(String name, String contents) async {
    final file = File(path(name));
    await file.create(exclusive: true);
    await file.writeAsString(contents, flush: true);
  }

  @override
  Future<void> makeDirectory(String name) =>
      Directory(path(name)).create().then((_) {});
}

class NativeVaultFiles implements VaultFiles {
  NativeVaultFiles(this.location);
  static const channel = MethodChannel('nl.mosterdzaad/vault');
  @override
  final VaultLocation location;
  Future<T?> call<T>(String method, String name, [String? contents]) {
    checkRelative(name);
    return channel.invokeMethod<T>(method, {
      'token': location.token,
      'path': name,
      'contents': ?contents,
    });
  }

  @override
  Future<List<String>> list(String directory) async =>
      List<String>.from(await call<List<dynamic>>('list', directory) ?? []);
  @override
  Future<String?> read(String name) => call<String>('read', name);
  @override
  Future<void> writeNew(String name, String contents) =>
      call<void>('writeNew', name, contents);
  @override
  Future<void> makeDirectory(String name) => call<void>('makeDirectory', name);
}

class VaultPicker {
  Future<List<VaultLocation>> listBooks() async => [];
  bool get usesNative =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  Future<VaultLocation?> pick() async {
    if (usesNative) {
      final result = await NativeVaultFiles.channel
          .invokeMapMethod<String, dynamic>('pickFolder');
      return result == null
          ? null
          : VaultLocation.fromJson(Map<String, dynamic>.from(result));
    }
    final path = await getDirectoryPath(
      confirmButtonText: 'Deze map gebruiken',
    );
    return path == null ? null : VaultLocation('path', path, p.basename(path));
  }

  VaultFiles files(VaultLocation location) => location.kind == 'path'
      ? LocalVaultFiles(location)
      : NativeVaultFiles(location);
  Future<VaultLocation> createChild(VaultLocation parent, String name) async {
    checkRelative(name);
    if (name.contains('/')) throw const FormatException('Kies één mapnaam.');
    if (parent.kind == 'path') {
      final path = p.join(parent.token, name);
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        throw const FormatException(
          'Deze map bestaat al. Kies een andere naam.',
        );
      }
      await Directory(path).create();
      return VaultLocation('path', path, name);
    }
    final result = await NativeVaultFiles.channel
        .invokeMapMethod<String, dynamic>('createChild', {
          'token': parent.token,
          'path': name,
        });
    return VaultLocation.fromJson(Map<String, dynamic>.from(result!));
  }
}

class RecentVaultStore {
  RecentVaultStore(this.directory);
  final String directory;
  File get file => File(p.join(directory, 'recent-studybook.json'));
  Future<VaultLocation?> load() async {
    if (!await file.exists()) return null;
    return VaultLocation.fromJson(
      Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map),
    );
  }

  Future<void> save(VaultLocation location) async {
    await Directory(directory).create(recursive: true);
    await file.writeAsString(jsonEncode(location.toJson()), flush: true);
  }

  Future<void> clear() async {
    if (await file.exists()) await file.delete();
  }
}
