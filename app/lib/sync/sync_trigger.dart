import 'dart:async';

/// Coalesces actual user/network events. Never schedules an idle poll.
class SyncTrigger {
  SyncTrigger({required this.canRun, required this.synchronize});

  final bool Function() canRun;
  final Future<void> Function() synchronize;
  Timer? _delay;
  bool _pending = false, _running = false, _disposed = false;

  void request({Duration delay = const Duration(milliseconds: 400)}) {
    if (_disposed) return;
    _delay?.cancel();
    _pending = true;
    _delay = Timer(delay, () {
      _delay = null;
      wake();
    });
  }

  /// Call after startup, saving, or a manual sync releases the controller.
  void wake() {
    if (_disposed || !_pending || _delay != null || _running || !canRun()) {
      return;
    }
    _pending = false;
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await synchronize();
    } finally {
      _running = false;
      wake();
    }
  }

  void cancel() {
    _delay?.cancel();
    _delay = null;
    _pending = false;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
