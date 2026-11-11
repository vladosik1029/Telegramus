import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegramus/src/accounts/auth_state.dart';
import 'package:telegramus/src/tdlib/td_client.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  late TdClient client;

  setUp(() {
    sent = [];
    client = TdClient(7, (id, json) {
      expect(id, 7);
      sent.add(jsonDecode(json) as Map<String, dynamic>);
    });
  });

  test('matches responses to requests by @extra', () async {
    final a = client.send({'@type': 'getMe'});
    final b = client.send({'@type': 'getOption', 'name': 'version'});
    expect(sent.map((r) => r['@extra']).toSet(), hasLength(2));

    client.handle({
      '@type': 'optionValueString',
      'value': '1.8.70',
      '@extra': sent[1]['@extra'],
      '@client_id': 7,
    });
    client.handle({
      '@type': 'user',
      'id': 1,
      '@extra': sent[0]['@extra'],
      '@client_id': 7,
    });

    expect((await a)['@type'], 'user');
    expect((await b)['value'], '1.8.70');
  });

  test('turns TDLib errors into TdException', () async {
    final f = client.send({'@type': 'checkAuthenticationCode', 'code': '1'});
    client.handle({
      '@type': 'error',
      'code': 400,
      'message': 'PHONE_CODE_INVALID',
      '@extra': sent.single['@extra'],
    });
    await expectLater(
      f,
      throwsA(
        isA<TdException>().having(
          (e) => e.message,
          'message',
          'PHONE_CODE_INVALID',
        ),
      ),
    );
  });

  test(
    'objects without @extra are updates; closed state ends the client',
    () async {
      final updates = <String>[];
      final done = client.updates
          .listen((u) => updates.add(u.type))
          .asFuture<void>();

      client.handle({'@type': 'updateOption', 'name': 'x'});
      client.handle({
        '@type': 'updateAuthorizationState',
        'authorization_state': {'@type': 'authorizationStateClosed'},
      });
      await done;

      expect(updates, ['updateOption', 'updateAuthorizationState']);
      expect(client.isClosed, isTrue);
      await expectLater(
        client.send({'@type': 'getMe'}),
        throwsA(isA<TdException>()),
      );
    },
  );

  test('maps authorization states', () {
    expect(
      AuthState.fromTd({'@type': 'authorizationStateWaitPhoneNumber'}),
      isA<AuthWaitPhone>(),
    );
    final code = AuthState.fromTd({
      '@type': 'authorizationStateWaitCode',
      'code_info': {
        'phone_number': '79000000000',
        'type': {'@type': 'authenticationCodeTypeSms', 'length': 5},
      },
    });
    expect(code, isA<AuthWaitCode>().having((c) => c.codeLength, 'length', 5));
    expect(
      AuthState.fromTd({'@type': 'authorizationStateWaitEmailAddress'}),
      isA<AuthUnsupported>(),
    );
  });
}
