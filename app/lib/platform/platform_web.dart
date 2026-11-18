import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../storage/search_index_web.dart';

Future<String> supportPath() async => '';
Future<String> cachePath() async => '';
Future<SearchIndex> createSearchIndex(String directory, String id) async =>
    SearchIndex();
Future<bool> requestPersistence() async {
  try {
    return (await web.window.navigator.storage.persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}

String get oauthRedirect =>
    Uri.parse(web.document.baseURI).resolve('auth.html').toString();
bool get oauthLoopback => false;

Future<void> downloadBackup(String name, String contents) async {
  final blob = web.Blob(
    [contents.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(link);
  link.click();
  link.remove();
  Future<void>.delayed(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(url),
  );
}
