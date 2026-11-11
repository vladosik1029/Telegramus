import 'dart:async';
import 'dart:convert';

/// A TDLib object as decoded from JSON (`{"@type": "...", ...}`).
typedef TdObject = Map<String, dynamic>;

extension TdObjectX on TdObject {
  String get type => this['@type'] as String;
}

class TdException implements Exception {
  TdException(this.code, this.message);
  final int code;
  final String message;

  @override
  String toString() => 'TdException($code): $message';
}

/// One TDLib instance, i.e. one Telegram account.
///
/// Requests get a unique `@extra` so their responses can be matched;
/// everything without `@extra` is an update and goes to [updates].
class TdClient {
  TdClient(this.id, this._sendRaw);

  final int id;
  final void Function(int clientId, String json) _sendRaw;

  final _updates = StreamController<TdObject>.broadcast(sync: true);
  final _pending = <int, Completer<TdObject>>{};
  int _nextExtra = 1;
  bool _closed = false;

  Stream<TdObject> get updates => _updates.stream;
  bool get isClosed => _closed;

  /// Sends a request and completes with its result, or throws [TdException].
  Future<TdObject> send(TdObject request) {
    if (_closed) {
      return Future.error(TdException(500, 'Client $id is closed'));
    }
    final extra = _nextExtra++;
    final completer = Completer<TdObject>();
    _pending[extra] = completer;
    _sendRaw(id, jsonEncode({...request, '@extra': extra}));
    return completer.future;
  }

  /// Sends a request without waiting for the result.
  void fire(TdObject request) {
    if (!_closed) _sendRaw(id, jsonEncode(request));
  }

  /// Called by [Tdlib] for every object addressed to this client.
  void handle(TdObject object) {
    final extra = object.remove('@extra');
    object.remove('@client_id');
    if (extra is int) {
      final completer = _pending.remove(extra);
      if (completer != null) {
        if (object.type == 'error') {
          completer.completeError(
            TdException(object['code'] as int, object['message'] as String),
          );
        } else {
          completer.complete(object);
        }
        return;
      }
    }
    _updates.add(object);

    if (object.type == 'updateAuthorizationState' &&
        (object['authorization_state'] as TdObject).type ==
            'authorizationStateClosed') {
      _markClosed();
    }
  }

  void _markClosed() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(TdException(500, 'Client $id closed'));
    }
    _pending.clear();
    // Let listeners see the final update before the stream ends.
    scheduleMicrotask(_updates.close);
  }
}
