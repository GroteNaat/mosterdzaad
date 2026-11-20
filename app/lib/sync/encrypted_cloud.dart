import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'crypto_box.dart';

class CloudChanged implements Exception {}

class CursorReset implements Exception {}

class CloudOffline implements Exception {
  @override
  String toString() => 'Offline — je wijzigingen staan in de wachtrij.';
}

class DropboxFailure implements Exception {
  const DropboxFailure(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

class CloudObject {
  CloudObject(this.bytes, this.revision);
  final Uint8List bytes;
  final String revision;
}

class CloudItem {
  CloudItem(this.path, this.revision, this.deleted, this.modified);
  final String path, revision, modified;
  final bool deleted;
  Map<String, dynamic> toJson() => {
    'path': path,
    'rev': revision,
    'deleted': deleted,
    'modified': modified,
  };
  factory CloudItem.fromJson(Map json) => CloudItem(
    json['path'] as String,
    json['rev'] as String,
    json['deleted'] as bool,
    json['modified'] as String,
  );
}

class CloudPage {
  CloudPage(this.items, this.cursor, this.more);
  final List<CloudItem> items;
  final String cursor;
  final bool more;
}

abstract interface class EncryptedCloud {
  Future<CloudObject?> download(String path);
  Future<String> upload(String path, Uint8List bytes, {String? revision});
  Future<CloudPage> list(String path, {String? cursor});
  Future<void> delete(String path, String revision);
}

class DropboxObjects implements EncryptedCloud {
  DropboxObjects(this.client, this.token);
  final http.Client client;
  final Future<String> Function(bool forceRefresh) token;
  final _random = Random();
  void _path(String path) {
    if (!RegExp(r'^/v2(?:/[a-z0-9-]+)*(?:\.enc)?$').hasMatch(path)) {
      throw const FormatException('Ongeldig versleuteld Dropbox-pad.');
    }
  }

  bool _tag(http.Response r, String tag) {
    if (r.statusCode != 409) return false;
    bool contains(Object? v) =>
        v is Map && (v['.tag'] == tag || v.values.any(contains));
    try {
      return contains((jsonDecode(r.body) as Map)['error']);
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _request(
    String host,
    String endpoint, {
    Object? json,
    Uint8List? bytes,
    Map<String, String> extra = const {},
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final request = http.Request('POST', Uri.https(host, '/2/$endpoint'));
        request.headers.addAll({
          'Authorization': 'Bearer ${await token(attempt == 1)}',
          'Content-Type': bytes == null
              ? 'application/json'
              : 'application/octet-stream',
          ...extra,
        });
        if (bytes != null) {
          request.bodyBytes = bytes;
        } else if (json != null) {
          request.body = jsonEncode(json);
        }
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 90));
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          buffer.add(chunk);
          if (buffer.length > CryptoBox.maxObjectBytes) {
            throw const FormatException('Dropbox-bestand te groot.');
          }
        }
        final r = http.Response.bytes(
          buffer.takeBytes(),
          response.statusCode,
          headers: response.headers,
        );
        if (r.statusCode == 401 && attempt == 0) continue;
        if ((r.statusCode == 429 || r.statusCode >= 500) && attempt < 4) {
          final seconds =
              int.tryParse(r.headers['retry-after'] ?? '') ?? (1 << attempt);
          await Future<void>.delayed(
            Duration(
              milliseconds: max(1, seconds) * 1000 + _random.nextInt(500),
            ),
          );
          continue;
        }
        if (r.statusCode == 401) {
          throw const DropboxFailure(
            'Koppel Dropbox opnieuw. Je wijzigingen zijn lokaal bewaard.',
            unauthorized: true,
          );
        }
        if (r.statusCode == 403) {
          throw const DropboxFailure(
            'Dropbox geeft geen toegang. Controleer de appmachtigingen.',
          );
        }
        if (r.statusCode == 429 || r.statusCode >= 500) throw CloudOffline();
        return r;
      } on http.ClientException {
        if (attempt >= 3) throw CloudOffline();
      } on TimeoutException {
        if (attempt >= 3) throw CloudOffline();
      }
      await Future<void>.delayed(
        Duration(milliseconds: (1 << attempt) * 1000 + _random.nextInt(500)),
      );
    }
  }

  void _success(http.Response r) {
    if (r.statusCode != 200) {
      throw DropboxFailure(
        'Dropbox-verzoek mislukt (${r.statusCode}). Lokale gegevens zijn behouden.',
      );
    }
  }

  @override
  Future<CloudObject?> download(String path) async {
    _path(path);
    final r = await _request(
      'content.dropboxapi.com',
      'files/download',
      extra: {
        'Dropbox-API-Arg': jsonEncode({'path': path}),
      },
    );
    if (_tag(r, 'not_found')) return null;
    _success(r);
    final meta = jsonDecode(r.headers['dropbox-api-result'] ?? '{}') as Map;
    if (meta['rev'] is! String) {
      throw const FormatException('Dropbox-bestandsversie ontbreekt.');
    }
    return CloudObject(r.bodyBytes, meta['rev'] as String);
  }

  @override
  Future<String> upload(
    String path,
    Uint8List bytes, {
    String? revision,
  }) async {
    _path(path);
    if (bytes.length > CryptoBox.maxObjectBytes) {
      throw const FormatException('Versleuteld bestand te groot.');
    }
    // Only the encrypted wire format is accepted by the cloud boundary.
    final object = jsonDecode(utf8.decode(bytes)) as Map;
    if ((object['header'] as Map?)?['format'] != 'mosterdzaad-encrypted') {
      throw const FormatException(
        'Dropbox accepteert uitsluitend versleutelde gegevens.',
      );
    }
    final r = await _request(
      'content.dropboxapi.com',
      'files/upload',
      bytes: bytes,
      extra: {
        'Dropbox-API-Arg': jsonEncode({
          'path': path,
          'mode': revision == null
              ? 'add'
              : {'.tag': 'update', 'update': revision},
          'autorename': false,
          'strict_conflict': true,
          'mute': true,
        }),
      },
    );
    if (_tag(r, 'conflict')) throw CloudChanged();
    _success(r);
    return (jsonDecode(r.body) as Map)['rev'] as String;
  }

  @override
  Future<CloudPage> list(String path, {String? cursor}) async {
    _path(path);
    final r = await _request(
      'api.dropboxapi.com',
      cursor == null ? 'files/list_folder' : 'files/list_folder/continue',
      json: cursor == null
          ? {
              'path': path,
              'recursive': true,
              'include_deleted': true,
              'limit': 500,
            }
          : {'cursor': cursor},
    );
    if (_tag(r, 'reset')) throw CursorReset();
    if (_tag(r, 'not_found')) return CloudPage([], '', false);
    _success(r);
    final json = jsonDecode(r.body) as Map;
    return CloudPage(
      [
        for (final item in json['entries'] as List)
          if (item['.tag'] != 'folder')
            CloudItem(
              item['path_lower'] as String,
              item['rev'] as String? ?? '',
              item['.tag'] == 'deleted',
              item['server_modified'] as String? ?? '',
            ),
      ],
      json['cursor'] as String,
      json['has_more'] as bool,
    );
  }

  @override
  Future<void> delete(String path, String revision) async {
    _path(path);
    final r = await _request(
      'api.dropboxapi.com',
      'files/delete_v2',
      json: {'path': path, 'parent_rev': revision},
    );
    if (_tag(r, 'not_found')) return;
    if (_tag(r, 'conflict')) throw CloudChanged();
    _success(r);
  }
}
