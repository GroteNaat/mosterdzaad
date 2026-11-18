import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../storage/search_index_native.dart';

Future<String> supportPath() async =>
    (await getApplicationSupportDirectory()).path;
Future<String> cachePath() async => (await getApplicationCacheDirectory()).path;
Future<SearchIndex> createSearchIndex(String directory, String id) async {
  await Directory(directory).create(recursive: true);
  return SearchIndex(File(p.join(directory, '$id.sqlite')));
}

Future<bool> requestPersistence() async => true;
String get oauthRedirect => Platform.isWindows || Platform.isLinux
    ? 'http://localhost:53682/auth'
    : 'nl.mosterdzaad://dropbox';
bool get oauthLoopback => Platform.isWindows || Platform.isLinux;

Future<void> downloadBackup(String name, String contents) async {
  // Native books are already ordinary files; UI offers browser export only.
  throw UnsupportedError('Kopieer de studieboekmap via de bestandsbeheerder.');
}
