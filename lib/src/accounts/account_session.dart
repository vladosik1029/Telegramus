import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../features/chats/chat_store.dart';
import '../tdlib/td_client.dart';
import 'auth_state.dart';

@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.photo,
  });

  factory UserProfile.fromTd(TdObject user) => UserProfile(
    id: user['id'] as int,
    firstName: user['first_name'] as String? ?? '',
    lastName: user['last_name'] as String? ?? '',
    phoneNumber: user['phone_number'] as String? ?? '',
    photo: (user['profile_photo'] as TdObject?)?['small'] as TdObject?,
  );

  final int id;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final TdObject? photo;

  String get fullName => '$firstName $lastName'.trim();
}

/// Everything that belongs to one logged-in (or logging-in) account:
/// its TDLib client, authorization state, profile, chat list and file cache.
///
/// Sessions live as long as the account exists, not as long as it is on
/// screen, so switching accounts is instant and every account keeps
/// receiving updates in the background.
class AccountSession {
  AccountSession({
    required this.accountId,
    required this.client,
    required this.config,
    required this.dataDir,
  }) {
    _sub = client.updates.listen(_onUpdate, onDone: _onClientDone);
    // A TDLib instance only starts after it receives its first request.
    client.fire({'@type': 'getOption', 'name': 'version'});
  }

  final String accountId;
  final TdClient client;
  final AppConfig config;
  final String dataDir;

  final authState = ValueNotifier<AuthState>(const AuthInitializing());
  final me = ValueNotifier<UserProfile?>(null);
  final unreadCount = ValueNotifier<int>(0);
  final chats = ChatStore();

  /// Fires when this account was logged out (from this or another device).
  final _loggedOut = Completer<void>();
  Future<void> get loggedOut => _loggedOut.future;

  final _closed = Completer<void>();
  final _fileDownloads = <int, Future<String?>>{};
  late final StreamSubscription<TdObject> _sub;
  bool _sawLoggingOut = false;
  bool _allChatsLoaded = false;
  bool _loadingChats = false;

  void _onUpdate(TdObject u) {
    switch (u.type) {
      case 'updateAuthorizationState':
        _onAuthState(u['authorization_state'] as TdObject);
      case 'updateUser':
        final user = u['user'] as TdObject;
        if (me.value?.id == user['id']) me.value = UserProfile.fromTd(user);
      case 'updateUnreadChatCount':
        if ((u['chat_list'] as TdObject).type == 'chatListMain') {
          unreadCount.value = u['unread_count'] as int;
        }
      case 'updateFile':
        final file = u['file'] as TdObject;
        final local = file['local'] as TdObject;
        if (local['is_downloading_completed'] == true) {
          _fileDownloads[file['id'] as int] = Future.value(
            local['path'] as String,
          );
        }
      default:
        chats.apply(u);
    }
  }

  void _onAuthState(TdObject raw) {
    final state = AuthState.fromTd(raw);
    authState.value = state;
    switch (raw.type) {
      case 'authorizationStateWaitTdlibParameters':
        _sendParameters();
      case 'authorizationStateReady':
        unawaited(_onReady());
      case 'authorizationStateLoggingOut':
        _sawLoggingOut = true;
      case 'authorizationStateClosed':
        if (_sawLoggingOut && !_loggedOut.isCompleted) _loggedOut.complete();
        if (!_closed.isCompleted) _closed.complete();
    }
  }

  void _onClientDone() {
    if (!_closed.isCompleted) _closed.complete();
  }

  void _sendParameters() {
    final locale = PlatformDispatcher.instance.locale;
    client.fire({
      '@type': 'setTdlibParameters',
      'use_test_dc': config.useTestDc,
      'database_directory': p.join(dataDir, 'db'),
      'files_directory': p.join(dataDir, 'files'),
      // Local database encryption is left empty in the skeleton; add a
      // per-account key from secure storage later.
      'database_encryption_key': '',
      'use_file_database': true,
      'use_chat_info_database': true,
      'use_message_database': true,
      'use_secret_chats': false,
      'api_id': config.apiId,
      'api_hash': config.apiHash,
      'system_language_code': locale.languageCode,
      'device_model': _deviceModel(),
      'system_version': Platform.operatingSystemVersion,
      'application_version': config.applicationVersion,
    });
  }

  Future<void> _onReady() async {
    try {
      me.value = UserProfile.fromTd(await client.send({'@type': 'getMe'}));
    } on TdException catch (e) {
      debugPrint('[$accountId] getMe failed: $e');
    }
    await loadMoreChats();
  }

  // ---- Auth actions -------------------------------------------------------

  Future<void> submitPhone(String phone) => client.send({
    '@type': 'setAuthenticationPhoneNumber',
    'phone_number': phone,
  });

  Future<void> submitCode(String code) =>
      client.send({'@type': 'checkAuthenticationCode', 'code': code});

  Future<void> submitPassword(String password) => client.send({
    '@type': 'checkAuthenticationPassword',
    'password': password,
  });

  Future<void> register(String firstName, String lastName) => client.send({
    '@type': 'registerUser',
    'first_name': firstName,
    'last_name': lastName,
  });

  // ---- Data ---------------------------------------------------------------

  Future<void> loadMoreChats() async {
    if (_allChatsLoaded || _loadingChats) return;
    _loadingChats = true;
    try {
      await client.send({
        '@type': 'loadChats',
        'chat_list': {'@type': 'chatListMain'},
        'limit': 50,
      });
    } on TdException catch (e) {
      // 404 = every chat is already loaded.
      if (e.code == 404) _allChatsLoaded = true;
    } finally {
      _loadingChats = false;
    }
  }

  /// Local path of a TDLib file, downloading it if needed.
  Future<String?> localPath(TdObject file) {
    final id = file['id'] as int;
    final local = file['local'] as TdObject?;
    if (local?['is_downloading_completed'] == true) {
      return _fileDownloads[id] ??= Future.value(local!['path'] as String);
    }
    return _fileDownloads[id] ??= client
        .send({
          '@type': 'downloadFile',
          'file_id': id,
          'priority': 1,
          'synchronous': true,
        })
        .then<String?>((f) {
          final path = (f['local'] as TdObject)['path'] as String;
          return path.isEmpty ? null : path;
        })
        .catchError((Object _) {
          _fileDownloads.remove(id);
          return null;
        });
  }

  // ---- Lifecycle ----------------------------------------------------------

  Future<void> logOut() async {
    try {
      await client.send({'@type': 'logOut'});
    } on TdException catch (e) {
      debugPrint('[$accountId] logOut failed: $e');
    }
    await _waitClosed();
  }

  /// Closes the TDLib instance (data stays on disk).
  Future<void> close() async {
    if (!client.isClosed) client.fire({'@type': 'close'});
    await _waitClosed();
  }

  Future<void> _waitClosed() =>
      _closed.future.timeout(const Duration(seconds: 15), onTimeout: () {});

  /// Stops listening to TDLib. Notifiers are left to the GC, because
  /// widgets of a just-removed account may still be unsubscribing.
  void dispose() => _sub.cancel();

  static String _deviceModel() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows PC';
    return 'Linux PC';
  }
}
