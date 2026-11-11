import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../features/chats/chat_store.dart';
import '../tdlib/tdlib.dart';
import 'account.dart';
import 'account_repository.dart';
import 'account_session.dart';
import 'auth_state.dart';

@immutable
class AccountsState {
  const AccountsState({required this.accounts, required this.activeId});

  final List<Account> accounts;
  final String activeId;

  Account get active => accounts.firstWhere((a) => a.id == activeId);

  /// Accounts that finished login, in the order they were added.
  List<Account> get authorized =>
      accounts.where((a) => a.isAuthorized).toList();

  AccountsState copyWith({List<Account>? accounts, String? activeId}) =>
      AccountsState(
        accounts: accounts ?? this.accounts,
        activeId: activeId ?? this.activeId,
      );
}

/// Owns every account and its [AccountSession].
///
/// All sessions run at the same time (TDLib's multi-client API), so the
/// active account is just a pointer: switching never re-creates clients.
class AccountsController extends AsyncNotifier<AccountsState> {
  final _sessions = <String, AccountSession>{};
  late AccountRepository _repo;
  late Tdlib _tdlib;
  late AppConfig _config;

  /// Sessions of removed accounts stay usable (inert) until the widgets
  /// showing them are gone, so a late rebuild never hits a missing session.
  AccountSession session(String accountId) =>
      _sessions[accountId] ?? _retired[accountId]!;
  final _retired = <String, AccountSession>{};

  @override
  Future<AccountsState> build() async {
    _config = ref.watch(appConfigProvider);
    _tdlib = await ref.watch(tdlibProvider.future);
    _repo = await AccountRepository.create();
    ref.onDispose(() {
      for (final s in _sessions.values) {
        unawaited(s.close().whenComplete(s.dispose));
      }
      _sessions.clear();
    });

    final stored = await _repo.load();
    var accounts = stored.accounts;
    if (accounts.isEmpty) {
      accounts = [Account(id: _repo.newAccountId())];
    }
    for (final a in accounts) {
      _startSession(a);
    }
    final activeId = accounts.any((a) => a.id == stored.activeId)
        ? stored.activeId!
        : accounts.first.id;
    final result = AccountsState(accounts: accounts, activeId: activeId);
    unawaited(_repo.save(result.accounts, result.activeId));
    return result;
  }

  AccountsState get _state => state.requireValue;

  void _set(AccountsState next) {
    state = AsyncData(next);
    unawaited(_repo.save(next.accounts, next.activeId));
  }

  void _startSession(Account account) {
    final session = AccountSession(
      accountId: account.id,
      client: _tdlib.createClient(),
      config: _config,
      dataDir: _repo.dataDirFor(account.id),
    );
    _sessions[account.id] = session;

    session.me.addListener(() {
      final me = session.me.value;
      if (me != null) _onProfile(account.id, me);
    });
    unawaited(session.loggedOut.then((_) => _forget(account.id)));
  }

  void _onProfile(String accountId, UserProfile me) {
    if (!state.hasValue) return;
    final current = _state;

    // Same Telegram user logged in twice: drop the new copy, keep the old.
    final duplicate = current.accounts
        .where((a) => a.id != accountId && a.userId == me.id)
        .firstOrNull;
    if (duplicate != null) {
      unawaited(_discard(accountId, switchTo: duplicate.id));
      return;
    }

    _set(
      current.copyWith(
        accounts: [
          for (final a in current.accounts)
            if (a.id == accountId)
              a.copyWith(
                userId: me.id,
                displayName: me.fullName,
                phoneNumber: me.phoneNumber,
              )
            else
              a,
        ],
      ),
    );
  }

  // ---- Public API ---------------------------------------------------------

  void switchTo(String accountId) {
    if (_state.activeId == accountId) return;
    if (!_state.accounts.any((a) => a.id == accountId)) return;
    _set(_state.copyWith(activeId: accountId));
  }

  /// Starts login for one more account and makes it active.
  void addAccount() {
    // Reuse an unfinished login instead of piling them up.
    final pending = _state.accounts.where((a) => !a.isAuthorized).firstOrNull;
    if (pending != null) {
      switchTo(pending.id);
      return;
    }
    final account = Account(id: _repo.newAccountId());
    _startSession(account);
    _set(
      AccountsState(
        accounts: [..._state.accounts, account],
        activeId: account.id,
      ),
    );
  }

  /// Aborts an unfinished login and deletes its local data.
  Future<void> cancelLogin(String accountId) async {
    final account = _state.accounts.firstWhere((a) => a.id == accountId);
    if (account.isAuthorized || _state.accounts.length < 2) return;
    await _discard(accountId);
  }

  Future<void> logOut(String accountId) async {
    final session = _sessions[accountId];
    if (session == null) return;
    await session.logOut();
    await _forget(accountId);
  }

  // ---- Internals ----------------------------------------------------------

  Future<void> _discard(String accountId, {String? switchTo}) async {
    final session = _sessions[accountId];
    await session?.close();
    await _forget(accountId, switchTo: switchTo);
  }

  /// Removes an account whose TDLib instance is already closed.
  Future<void> _forget(String accountId, {String? switchTo}) async {
    final session = _sessions.remove(accountId);
    if (session == null) return;
    _retired[accountId] = session;

    var accounts = _state.accounts.where((a) => a.id != accountId).toList();
    if (accounts.isEmpty) {
      // Never leave the app without an account: start a fresh login.
      final fresh = Account(id: _repo.newAccountId());
      _startSession(fresh);
      accounts = [fresh];
    }
    final activeId =
        switchTo ??
        (_state.activeId == accountId ? accounts.first.id : _state.activeId);
    _set(AccountsState(accounts: accounts, activeId: activeId));

    session.dispose();
    await _repo.deleteData(accountId);
  }
}

final accountsProvider =
    AsyncNotifierProvider<AccountsController, AccountsState>(
      AccountsController.new,
    );

final activeAccountIdProvider = Provider<String?>(
  (ref) => ref.watch(accountsProvider).value?.activeId,
);

final sessionProvider = Provider.autoDispose.family<AccountSession, String>(
  (ref, id) => ref.read(accountsProvider.notifier).session(id),
);

extension _ListenableRef on Ref {
  /// Rebuilds the provider whenever [listenable] changes.
  T watchListenable<T>(ValueListenable<T> listenable) {
    void onChange() => invalidateSelf();
    listenable.addListener(onChange);
    onDispose(() => listenable.removeListener(onChange));
    return listenable.value;
  }
}

final authStateProvider = Provider.autoDispose.family<AuthState, String>(
  (ref, id) => ref.watchListenable(ref.watch(sessionProvider(id)).authState),
);

final meProvider = Provider.autoDispose.family<UserProfile?, String>(
  (ref, id) => ref.watchListenable(ref.watch(sessionProvider(id)).me),
);

final unreadCountProvider = Provider.autoDispose.family<int, String>(
  (ref, id) => ref.watchListenable(ref.watch(sessionProvider(id)).unreadCount),
);

final chatListProvider = Provider.autoDispose.family<List<ChatSummary>, String>(
  (ref, id) {
    final store = ref.watch(sessionProvider(id)).chats;
    void onChange() => ref.invalidateSelf();
    store.addListener(onChange);
    ref.onDispose(() => store.removeListener(onChange));
    return store.chats;
  },
);
