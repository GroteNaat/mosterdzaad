import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:workmanager/workmanager.dart';

import 'dropbox_auth.dart';
import 'encrypted_cloud.dart';
import 'local_state_native.dart';

const _task = 'nl.mosterdzaad.sync';
Future<void>? _initialization;
Future<void> scheduleBackground(String directory, String book) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await (_initialization ??= Workmanager().initialize(syncDispatcher));
  final data = {'directory': directory, 'book': book};
  if (Platform.isIOS) {
    await Workmanager().registerProcessingTask(
      _task,
      _task,
      inputData: data,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } else {
    await Workmanager().registerOneOffTask(
      _task,
      _task,
      inputData: data,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
  }
}

Future<void> cancelBackground() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await Workmanager().cancelByUniqueName(_task);
  }
}

/// A headless task only transports already-encrypted durable outbox objects.
/// It never accesses a user-selected folder or changes the foreground journal.
/// Foreground sync verifies the remote objects before acknowledging them.
@pragma('vm:entry-point')
void syncDispatcher() {
  Workmanager().executeTask((task, input) async {
    if (input?['directory'] is! String || input?['book'] is! String) {
      return true;
    }
    final store = LocalStateStore(input!['directory'] as String),
        secrets = SecretStore();
    final book = input['book'] as String;
    final source = await store.read('background-$book');
    if (source == null) return true;
    final job = jsonDecode(source) as Map;
    final refresh = await secrets.read('dropbox-refresh');
    if (refresh == null) return true;
    final client = http.Client();
    try {
      DropboxSession? session;
      final cloud = DropboxObjects(client, (force) async {
        if (session == null || !session!.valid || force) {
          session = await refreshDropbox(refresh, client);
        }
        return session!.accessToken;
      });
      final dataset = job['dataset'] as String;
      final envelope = await cloud.download('/v2/$dataset/key.enc');
      // Account changes, password changes and rollback require a foreground
      // check; never upload blindly into another account or dataset.
      if (envelope == null ||
          sha256.convert(envelope.bytes).toString() != job['envelopeHash']) {
        return true;
      }
      final watch = Stopwatch()..start();
      for (final entry in (job['outbox'] as Map).entries) {
        if (watch.elapsed > const Duration(seconds: 20)) return false;
        if (await secrets.read('dropbox-refresh') != refresh) return true;
        final current = await store.read('background-$book');
        if (current == null ||
            !((jsonDecode(current) as Map)['outbox'] as Map).containsKey(
              entry.key,
            )) {
          continue;
        }
        final bytes = base64Decode(entry.value as String);
        final path = '/v2/$dataset/changes/${entry.key}.enc';
        try {
          await cloud.upload(path, bytes);
        } on CloudChanged {
          final existing = await cloud.download(path);
          if (existing == null ||
              sha256.convert(existing.bytes) != sha256.convert(bytes)) {
            return true;
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  });
}
