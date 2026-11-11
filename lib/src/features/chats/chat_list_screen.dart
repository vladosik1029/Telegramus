import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/accounts_controller.dart';
import '../accounts/account_switcher.dart';
import '../common/avatar.dart';
import 'chat_store.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({
    super.key,
    required this.accountId,
    required this.useDrawer,
  });

  final String accountId;

  /// Phones get a drawer; wide layouts show [AccountRail] instead.
  final bool useDrawer;

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(sessionProvider(widget.accountId)).loadMoreChats();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatListProvider(widget.accountId));
    final account = ref.watch(accountsProvider).requireValue.active;

    return Scaffold(
      appBar: AppBar(
        title: Text(account.label),
        actions: [
          if (!widget.useDrawer)
            IconButton(
              tooltip: 'Выйти из аккаунта',
              icon: const Icon(Icons.logout),
              onPressed: () => confirmLogOut(context, ref, account),
            ),
        ],
      ),
      drawer: widget.useDrawer ? const AccountDrawer() : null,
      body: chats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              controller: _scroll,
              itemCount: chats.length,
              itemBuilder: (context, i) =>
                  _ChatTile(accountId: widget.accountId, chat: chats[i]),
            ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.accountId, required this.chat});

  final String accountId;
  final ChatSummary chat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: TdAvatar(
        accountId: accountId,
        title: chat.title,
        seed: chat.id,
        file: chat.photo,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (chat.lastMessageDate > 0)
            Text(
              formatChatDate(chat.lastMessageDate, DateTime.now()),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              chat.lastMessage ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.unreadMentionCount > 0)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.alternate_email, size: 18),
            ),
          if (chat.unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Badge(label: Text('${chat.unreadCount}')),
            )
          else if (chat.isPinned)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.push_pin_outlined, size: 16),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(chat.title)),
            body: const Center(
              child: Text('Экран чата появится на следующем этапе'),
            ),
          ),
        ),
      ),
    );
  }
}

String formatChatDate(int unixSeconds, DateTime now) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '${two(d.hour)}:${two(d.minute)}';
  if (diff > 0 && diff < 7) {
    return const ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'][d.weekday - 1];
  }
  return '${two(d.day)}.${two(d.month)}.${two(d.year % 100)}';
}
