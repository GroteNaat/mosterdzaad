import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const dropboxAppKey = String.fromEnvironment(
  'DROPBOX_APP_KEY',
  defaultValue: '01vxprgsncvmvze',
);

class DropboxSession {
  const DropboxSession(this.accessToken, this.expiresAt);
  final String accessToken;
  final DateTime expiresAt;
  bool get valid =>
      DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 1)));
}

/// Single-use PKCE challenge. No client secret, no persistent access/refresh token.
class DropboxAuthorization {
  DropboxAuthorization({
    required this.redirect,
    this.appKey = dropboxAppKey,
    String? verifier,
    String? state,
  }) : verifier = verifier ?? _random(),
       state = state ?? _random();
  final String redirect, appKey, verifier, state;
  bool _used = false;
  static String _random() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  String get challenge => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
  Uri get url => Uri.https('www.dropbox.com', '/oauth2/authorize', {
    'client_id': appKey,
    'response_type': 'code',
    'redirect_uri': redirect,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
    'state': state,
    'token_access_type': 'online',
    'scope': 'files.metadata.read files.content.read files.content.write',
  });

  Future<DropboxSession> exchange(String callback, http.Client client) async {
    if (_used) throw const FormatException('Deze aanmelding is al verwerkt.');
    _used = true;
    final uri = Uri.parse(callback), expected = Uri.parse(redirect);
    if (uri.scheme != expected.scheme ||
        uri.host != expected.host ||
        uri.port != expected.port ||
        uri.path != expected.path ||
        uri.queryParameters['state'] != state) {
      throw const FormatException(
        'De Dropbox-aanmelding kon niet worden gecontroleerd. Probeer opnieuw.',
      );
    }
    if (uri.queryParameters.containsKey('error')) {
      throw const FormatException(
        'Dropbox-aanmelding geannuleerd of geweigerd.',
      );
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const FormatException('Dropbox stuurde geen aanmeldcode.');
    }
    final response = await client
        .post(
          Uri.https('api.dropboxapi.com', '/oauth2/token'),
          body: {
            'grant_type': 'authorization_code',
            'code': code,
            'client_id': appKey,
            'redirect_uri': redirect,
            'code_verifier': verifier,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const FormatException(
        'Dropbox-aanmelding mislukt. Controleer de app key, toegangsrechten en het redirect-adres.',
      );
    }
    final json = jsonDecode(response.body) as Map;
    if (json['access_token'] is! String || json['expires_in'] is! num) {
      throw const FormatException('Ongeldig antwoord van Dropbox.');
    }
    return DropboxSession(
      json['access_token'] as String,
      DateTime.now().add(
        Duration(seconds: (json['expires_in'] as num).toInt()),
      ),
    );
  }
}
