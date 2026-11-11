import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'td_client.dart';
import 'td_json_bindings.dart';

/// Owns the loaded TDLib library, the single receive loop, and all clients.
class Tdlib {
  Tdlib._(this._bindings, this._isolate, this._port, this.libraryPath) {
    _port.listen(_dispatch);
  }

  final TdJsonBindings _bindings;
  final Isolate _isolate;
  final ReceivePort _port;
  final String? libraryPath;
  final _clients = <int, TdClient>{};

  /// Loads TDLib and starts the receive loop in a background isolate,
  /// because `td_receive` blocks.
  static Future<Tdlib> start({int logVerbosity = 1}) async {
    final path = resolveTdJsonPath();
    final bindings = TdJsonBindings(openTdJson(path));
    bindings.execute(
      jsonEncode({
        '@type': 'setLogVerbosityLevel',
        'new_verbosity_level': logVerbosity,
      }),
    );
    final port = ReceivePort('tdlib-receive');
    final isolate = await Isolate.spawn(
      _receiveLoop,
      _LoopArgs(path, port.sendPort),
      debugName: 'tdlib-receive',
    );
    return Tdlib._(bindings, isolate, port, path);
  }

  TdClient createClient() {
    final id = _bindings.createClientId();
    final client = TdClient(id, _bindings.send);
    _clients[id] = client;
    return client;
  }

  /// Synchronous TDLib call (only for methods documented as such).
  TdObject? execute(TdObject request) {
    final res = _bindings.execute(jsonEncode(request));
    return res == null ? null : jsonDecode(res) as TdObject;
  }

  void _dispatch(dynamic message) {
    if (message is! Map) return;
    final object = message.cast<String, dynamic>();
    final clientId = object['@client_id'];
    if (clientId is! int) return;
    final client = _clients[clientId];
    if (client == null) return;
    client.handle(object);
    if (client.isClosed) _clients.remove(clientId);
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _port.close();
  }
}

class _LoopArgs {
  const _LoopArgs(this.libraryPath, this.sendPort);
  final String? libraryPath;
  final SendPort sendPort;
}

void _receiveLoop(_LoopArgs args) {
  final bindings = TdJsonBindings(openTdJson(args.libraryPath));
  while (true) {
    final raw = bindings.receive(1.0);
    if (raw != null) {
      // Decode here so the UI isolate does less work.
      args.sendPort.send(jsonDecode(raw));
    }
  }
}

final tdlibProvider = FutureProvider<Tdlib>((ref) async {
  final tdlib = await Tdlib.start();
  ref.onDispose(tdlib.dispose);
  return tdlib;
});
