import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _CreateClientIdNative = Int32 Function();
typedef _CreateClientIdDart = int Function();
typedef _SendNative = Void Function(Int32, Pointer<Utf8>);
typedef _SendDart = void Function(int, Pointer<Utf8>);
typedef _ReceiveNative = Pointer<Utf8> Function(Double);
typedef _ReceiveDart = Pointer<Utf8> Function(double);
typedef _ExecuteNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ExecuteDart = Pointer<Utf8> Function(Pointer<Utf8>);

/// Thin FFI wrapper over TDLib's JSON interface (`td_json_client.h`).
///
/// Uses the multi-client API: one process can host many TDLib instances
/// (one per account), and a single `td_receive` loop serves all of them.
class TdJsonBindings {
  TdJsonBindings(DynamicLibrary lib)
    : _createClientId = lib
          .lookupFunction<_CreateClientIdNative, _CreateClientIdDart>(
            'td_create_client_id',
          ),
      _send = lib.lookupFunction<_SendNative, _SendDart>('td_send'),
      _receive = lib.lookupFunction<_ReceiveNative, _ReceiveDart>('td_receive'),
      _execute = lib.lookupFunction<_ExecuteNative, _ExecuteDart>('td_execute');

  final _CreateClientIdDart _createClientId;
  final _SendDart _send;
  final _ReceiveDart _receive;
  final _ExecuteDart _execute;

  int createClientId() => _createClientId();

  void send(int clientId, String request) {
    final ptr = request.toNativeUtf8();
    try {
      _send(clientId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Blocks for up to [timeoutSeconds]. Must never be called concurrently.
  String? receive(double timeoutSeconds) {
    final res = _receive(timeoutSeconds);
    return res == nullptr ? null : res.toDartString();
  }

  String? execute(String request) {
    final ptr = request.toNativeUtf8();
    try {
      final res = _execute(ptr);
      return res == nullptr ? null : res.toDartString();
    } finally {
      malloc.free(ptr);
    }
  }
}

/// Where to load TDLib from. `null` means "symbols are already linked into
/// the process" (iOS static linking).
String? resolveTdJsonPath() {
  final override = Platform.environment['TDJSON_PATH'];
  if (override != null && override.isNotEmpty) return override;

  final exeDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isIOS) return null;
  if (Platform.isAndroid) return 'libtdjson.so';
  if (Platform.isWindows) {
    final local = p.join(exeDir, 'tdjson.dll');
    return File(local).existsSync() ? local : 'tdjson.dll';
  }
  if (Platform.isMacOS) {
    final bundled = p.normalize(
      p.join(exeDir, '..', 'Frameworks', 'libtdjson.dylib'),
    );
    return File(bundled).existsSync() ? bundled : 'libtdjson.dylib';
  }
  // Linux: the Flutter bundle keeps native libraries in `<bundle>/lib`.
  final bundled = p.join(exeDir, 'lib', 'libtdjson.so');
  return File(bundled).existsSync() ? bundled : 'libtdjson.so';
}

DynamicLibrary openTdJson(String? path) =>
    path == null ? DynamicLibrary.process() : DynamicLibrary.open(path);
