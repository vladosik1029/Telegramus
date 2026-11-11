import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/account.dart';
import '../../accounts/accounts_controller.dart';
import '../common/avatar.dart';

/// Avatar of a local account, with its own unread counter as a badge.
class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({
    super.key,
    required this.account,
    this.radius = 20,
    this.showBadge = true,
  });

  final Account account;
  final double radius;
  final bool showBadge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider(account.id));
    final unread = showBadge ? ref.watch(unreadCountProvider(account.id)) : 0;
    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: TdAvatar(
        accountId: account.id,
        title: account.label,
        seed: account.userId ?? account.id.hashCode,
        file: me?.photo,
        radius: radius,
      ),
    );
  }
}

/// Vertical column of account avatars for wide (desktop/tablet) layouts.
class AccountRail extends ConsumerWidget {
  const AccountRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountsProvider).requireValue;
    final controller = ref.read(accountsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 72,
      color: scheme.surfaceContainer,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final (i, a) in state.accounts.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Tooltip(
                      message: i < 9 ? '${a.label}  (Ctrl+${i + 1})' : a.label,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => controller.switchTo(a.id),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: 2,
                                color: a.id == state.activeId
                                    ? scheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: AccountAvatar(account: a, radius: 22),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Добавить аккаунт',
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: controller.addAccount,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Drawer for narrow (phone) layouts.
class AccountDrawer extends ConsumerWidget {
  const AccountDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountsProvider).requireValue;
    final controller = ref.read(accountsProvider.notifier);
    final active = state.active;
    final me = ref.watch(meProvider(active.id));
    final theme = Theme.of(context);

    void close() => Navigator.of(context).pop();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AccountAvatar(account: active, radius: 32, showBadge: false),
                  const SizedBox(height: 12),
                  Text(active.label, style: theme.textTheme.titleMedium),
                  if (me != null && me.phoneNumber.isNotEmpty)
                    Text(
                      '+${me.phoneNumber}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const Divider(),
            for (final a in state.accounts)
              if (a.id != active.id)
                ListTile(
                  leading: AccountAvatar(account: a),
                  title: Text(a.label),
                  onTap: () {
                    close();
                    controller.switchTo(a.id);
                  },
                ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Добавить аккаунт'),
              onTap: () {
                close();
                controller.addAccount();
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: const Text('Выйти из этого аккаунта'),
              // The dialog opens over the drawer; logging out rebuilds the
              // whole account screen, which closes the drawer too.
              onTap: () => confirmLogOut(context, ref, active),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> confirmLogOut(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Выйти из аккаунта?'),
      content: Text(
        '${account.label} будет удалён с этого устройства вместе с кэшем.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Выйти'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(accountsProvider.notifier).logOut(account.id);
  }
}
