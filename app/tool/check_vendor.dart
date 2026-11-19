import 'dart:io';

import 'package:crypto/crypto.dart';

/// Pin offline JS/WASM to the reviewed package/source versions. Run directly
/// with the Dart VM to avoid invoking native build hooks for this file check.
Future<void> main() async {
  const hashes = {
    'sodium.js':
        'dedbeb3a33be1cf9d1b923832c5f188f990a6ed543f94eae366c5e73aed3c34e',
    'loro_crdt_ffi.js':
        'c0618064cfd549debe38c1d7799d2f3f8b8e46879ce7ee4abc31ba77d9ab6089',
    'loro_crdt_ffi.wasm':
        '68b17b08a820dd8b1672aff541bb16ada90838dd637bf74a53d0d5de0c0c7c79',
  };
  for (final item in hashes.entries) {
    if (sha256
            .convert(await File('web/${item.key}').readAsBytes())
            .toString() !=
        item.value) {
      throw StateError('Unexpected vendor asset: ${item.key}');
    }
  }
  stdout.writeln('Pinned Loro and libsodium browser assets verified.');
}
