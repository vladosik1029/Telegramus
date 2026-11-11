// Runs against a real TDLib build. Skipped unless TDJSON_PATH is set:
//   TDJSON_PATH=/path/to/libtdjson.so flutter test test/tdlib_integration_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegramus/src/accounts/account_session.dart';
import 'package:telegramus/src/accounts/auth_state.dart';
import 'package:telegramus/src/config/app_config.dart';
import 'package:telegramus/src/tdlib/tdlib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hasTdlib = (Platform.environment['TDJSON_PATH'] ?? '').isNotEmpty;

  test(
    'two accounts run separate TDLib instances and reach the phone step',
    () async {
      final tdlib = await Tdlib.start(logVerbosity: 0);
      addTearDown(tdlib.dispose);
      final tmp = await Directory.systemTemp.createTemp('telegramus_test');
      addTearDown(() => tmp.delete(recursive: true));

      const config = AppConfig(
        apiId: 1,
        apiHash: '00000000000000000000000000000000',
      );
      final sessions = [
        for (final id in ['a', 'b'])
          AccountSession(
            accountId: id,
            client: tdlib.createClient(),
            config: config,
            dataDir: '${tmp.path}/$id',
          ),
      ];
      expect(sessions[0].client.id, isNot(sessions[1].client.id));

      Future<void> waitPhone(AccountSession s) {
        final done = Completer<void>();
        void check() {
          if (s.authState.value is AuthWaitPhone && !done.isCompleted) {
            done.complete();
          }
        }

        s.authState.addListener(check);
        check();
        return done.future.timeout(const Duration(seconds: 30));
      }

      await Future.wait(sessions.map(waitPhone));
      for (final s in sessions) {
        expect(Directory('${tmp.path}/${s.accountId}/db').existsSync(), isTrue);
      }
      await Future.wait(sessions.map((s) => s.close()));
      for (final s in sessions) {
        expect(s.client.isClosed, isTrue);
      }
    },
    skip: hasTdlib ? false : 'Set TDJSON_PATH to run against real TDLib',
  );
}
