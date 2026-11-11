import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/accounts_controller.dart';
import '../../accounts/auth_state.dart';
import '../auth/auth_screen.dart';
import '../chats/chat_list_screen.dart';
import 'account_switcher.dart';

/// Shell around the active account: account rail on wide screens, drawer
/// on phones, and Ctrl/Cmd+1..9 to jump between accounts on desktop.
class AccountShell extends ConsumerWidget {
  const AccountShell({super.key});

  static const wideBreakpoint = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountsProvider).requireValue;
    final controller = ref.read(accountsProvider.notifier);
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    final bindings = <ShortcutActivator, VoidCallback>{};
    for (var i = 0; i < state.accounts.length && i < 9; i++) {
      final id = state.accounts[i].id;
      final key = LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i);
      bindings[SingleActivator(key, control: true)] = () =>
          controller.switchTo(id);
      bindings[SingleActivator(key, meta: true)] = () =>
          controller.switchTo(id);
    }

    // Keyed by account id: switching accounts builds a fresh subtree, so no
    // scroll position, form field or navigation stack leaks between them.
    final content = _AccountContent(
      key: ValueKey(state.activeId),
      accountId: state.activeId,
      useDrawer: !wide,
    );

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: wide
            ? Row(
                children: [
                  const AccountRail(),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }
}

class _AccountContent extends ConsumerWidget {
  const _AccountContent({
    super.key,
    required this.accountId,
    required this.useDrawer,
  });

  final String accountId;
  final bool useDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider(accountId));
    if (auth is AuthReady) {
      // Its own navigator, so an opened chat belongs to this account only.
      return Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) =>
              ChatListScreen(accountId: accountId, useDrawer: useDrawer),
        ),
      );
    }
    return AuthScreen(accountId: accountId);
  }
}
