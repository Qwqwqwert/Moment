import 'dart:async';

typedef PendingWorkFlusher = Future<void> Function();

/// Coordinates editor debounces and other in-flight writes before desktop exit.
class PendingWorkCoordinator {
  final Set<PendingWorkFlusher> _flushers = {};
  final Set<Future<void>> _operations = {};

  void register(PendingWorkFlusher flusher) => _flushers.add(flusher);
  void unregister(PendingWorkFlusher flusher) => _flushers.remove(flusher);

  Future<T> track<T>(Future<T> operation) {
    final completion = operation.then<void>((_) {}, onError: (_) {});
    _operations.add(completion);
    completion.whenComplete(() => _operations.remove(completion));
    return operation;
  }

  Future<void> flush() async {
    for (final flusher in [..._flushers]) {
      await flusher();
    }
    while (_operations.isNotEmpty) {
      await Future.wait([..._operations]);
    }
  }
}
