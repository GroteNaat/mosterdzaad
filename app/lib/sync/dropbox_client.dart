import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/entry.dart';
import '../storage/vault_snapshot.dart';

class CloudVersion {
  const CloudVersion(this.snapshot, this.revision);
  final VaultSnapshot snapshot;
  final String revision;
}

class CloudBook {
  const CloudBook(this.id, this.modified);
  final String id, modified;
}

class CloudChanged implements Exception {}

class DropboxFailure implements Exception {
  const DropboxFailure(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

abstract interface class CloudStore {
  Future<CloudVersion?> read(String id);
  Future<void> write(
    String id,
    VaultSnapshot snapshot,
    String? expectedRevision,
  );
}

class DropboxClient implements CloudStore {
  DropboxClient(this.client, this.token);
  final http.Client client;
  final String token;
  String path(String id) {
    if (!uuidPattern.hasMatch(id)) {
      throw const FormatException('Ongeldige studieboek-ID.');
    }
    return '/$id.mosterdzaad.json';
  }

  Map<String, String> get headers => {'Authorization': 'Bearer $token'};
  Never failure(http.Response response) {
    throw DropboxFailure(switch (response.statusCode) {
      401 =>
        'Je Dropbox-sessie is verlopen. Meld opnieuw aan; lokale wijzigingen zijn bewaard.',
      403 => 'Dropbox geeft geen toegang. Controleer de appmachtigingen.',
      429 => 'Dropbox is tijdelijk druk. Probeer over enkele minuten opnieuw.',
      507 => 'Je Dropbox is vol. Maak ruimte vrij en probeer opnieuw.',
      _ =>
        'Dropbox is niet beschikbaar (${response.statusCode}). Je lokale gegevens zijn behouden.',
    }, unauthorized: response.statusCode == 401);
  }

  bool _tagged(http.Response response, String tag) {
    if (response.statusCode != 409) return false;
    try {
      final error = (jsonDecode(response.body) as Map)['error'];
      bool contains(dynamic value) =>
          value is Map && (value['.tag'] == tag || value.values.any(contains));
      return contains(error);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CloudVersion?> read(String id) async {
    final request =
        http.Request(
            'POST',
            Uri.https('content.dropboxapi.com', '/2/files/download'),
          )
          ..headers.addAll({
            ...headers,
            'Dropbox-API-Arg': jsonEncode({'path': path(id)}),
          });
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > VaultSnapshot.maxBytes) {
        throw const FormatException(
          'Het Dropbox-studieboek is groter dan 20 MB.',
        );
      }
    }
    final body = http.Response.bytes(
      bytes,
      response.statusCode,
      headers: response.headers,
    );
    if (_tagged(body, 'not_found')) return null;
    if (body.statusCode != 200) failure(body);
    final metadata =
        jsonDecode(body.headers['dropbox-api-result'] ?? '{}') as Map;
    final revision = metadata['rev'];
    if (revision is! String || revision.isEmpty) {
      throw const FormatException('Dropbox gaf geen bestandsversie terug.');
    }
    final snapshot = VaultSnapshot.decode(utf8.decode(bytes));
    if (snapshot.id != id) {
      throw const FormatException(
        'De Dropbox-bestandsnaam past niet bij dit studieboek.',
      );
    }
    return CloudVersion(snapshot, revision);
  }

  @override
  Future<void> write(
    String id,
    VaultSnapshot snapshot,
    String? expectedRevision,
  ) async {
    final response = await client
        .post(
          Uri.https('content.dropboxapi.com', '/2/files/upload'),
          headers: {
            ...headers,
            'Content-Type': 'application/octet-stream',
            'Dropbox-API-Arg': jsonEncode({
              'path': path(id),
              'mode': expectedRevision == null
                  ? 'add'
                  : {'.tag': 'update', 'update': expectedRevision},
              'autorename': false,
              'strict_conflict': true,
              'mute': true,
            }),
          },
          body: utf8.encode(snapshot.encode()),
        )
        .timeout(const Duration(seconds: 60));
    if (_tagged(response, 'conflict')) throw CloudChanged();
    if (response.statusCode != 200) failure(response);
  }

  Future<List<CloudBook>> listBooks() async {
    final books = <CloudBook>[];
    String? cursor;
    do {
      final response = await client
          .post(
            Uri.https(
              'api.dropboxapi.com',
              cursor == null
                  ? '/2/files/list_folder'
                  : '/2/files/list_folder/continue',
            ),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode(
              cursor == null
                  ? {'path': '', 'recursive': false}
                  : {'cursor': cursor},
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) failure(response);
      final json = jsonDecode(response.body) as Map;
      for (final item in json['entries'] as List) {
        final name = item['name'] as String;
        if (item['.tag'] == 'file' && name.endsWith('.mosterdzaad.json')) {
          final id = name.replaceFirst('.mosterdzaad.json', '');
          if (uuidPattern.hasMatch(id)) {
            books.add(CloudBook(id, item['server_modified'] as String));
          }
        }
      }
      cursor = json['has_more'] == true ? json['cursor'] as String : null;
      if (books.length > 1000) {
        throw const FormatException('Te veel Dropbox-studieboeken.');
      }
    } while (cursor != null);
    return books;
  }
}
