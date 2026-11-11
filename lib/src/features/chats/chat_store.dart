import 'package:flutter/foundation.dart';

import '../../tdlib/td_client.dart';

@immutable
class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    this.photo,
    this.lastMessage,
    this.lastMessageDate = 0,
    this.unreadCount = 0,
    this.unreadMentionCount = 0,
    this.order = 0,
    this.isPinned = false,
  });

  final int id;
  final String title;

  /// TDLib `file` object of the small chat photo, if any.
  final TdObject? photo;
  final String? lastMessage;

  /// Unix time, seconds.
  final int lastMessageDate;
  final int unreadCount;
  final int unreadMentionCount;

  /// Position in the main chat list; 0 means "not in the list".
  final int order;
  final bool isPinned;

  ChatSummary copyWith({
    String? title,
    TdObject? Function()? photo,
    String? Function()? lastMessage,
    int? lastMessageDate,
    int? unreadCount,
    int? unreadMentionCount,
    int? order,
    bool? isPinned,
  }) => ChatSummary(
    id: id,
    title: title ?? this.title,
    photo: photo != null ? photo() : this.photo,
    lastMessage: lastMessage != null ? lastMessage() : this.lastMessage,
    lastMessageDate: lastMessageDate ?? this.lastMessageDate,
    unreadCount: unreadCount ?? this.unreadCount,
    unreadMentionCount: unreadMentionCount ?? this.unreadMentionCount,
    order: order ?? this.order,
    isPinned: isPinned ?? this.isPinned,
  );
}

/// Keeps one account's main chat list in sync with TDLib updates.
///
/// TDLib streams the list as `updateNewChat` + `updateChatPosition` etc.;
/// the order of the list is defined by `position.order` (bigger = higher).
class ChatStore extends ChangeNotifier {
  final _chats = <int, ChatSummary>{};
  List<ChatSummary>? _sorted;

  List<ChatSummary> get chats => _sorted ??= _computeSorted();

  ChatSummary? operator [](int id) => _chats[id];

  List<ChatSummary> _computeSorted() {
    final list = _chats.values.where((c) => c.order != 0).toList()
      ..sort((a, b) => b.order.compareTo(a.order));
    return List.unmodifiable(list);
  }

  /// Applies a TDLib update. Returns true if the update was relevant.
  bool apply(TdObject update) {
    final changed = _apply(update);
    if (changed) {
      _sorted = null;
      notifyListeners();
    }
    return changed;
  }

  bool _apply(TdObject u) {
    switch (u.type) {
      case 'updateNewChat':
        final chat = u['chat'] as TdObject;
        final id = chat['id'] as int;
        final last = chat['last_message'] as TdObject?;
        final main = _mainPosition(chat['positions'] as List?);
        _chats[id] = ChatSummary(
          id: id,
          title: chat['title'] as String? ?? '',
          photo: _smallPhoto(chat['photo'] as TdObject?),
          lastMessage: last == null ? null : describeMessage(last),
          lastMessageDate: last?['date'] as int? ?? 0,
          unreadCount: chat['unread_count'] as int? ?? 0,
          unreadMentionCount: chat['unread_mention_count'] as int? ?? 0,
          order: _order(main),
          isPinned: main?['is_pinned'] as bool? ?? false,
        );
        return true;
      case 'updateChatTitle':
        return _update(u, (c) => c.copyWith(title: u['title'] as String));
      case 'updateChatPhoto':
        return _update(
          u,
          (c) => c.copyWith(photo: () => _smallPhoto(u['photo'] as TdObject?)),
        );
      case 'updateChatLastMessage':
        final last = u['last_message'] as TdObject?;
        final main = _mainPosition(u['positions'] as List?);
        return _update(
          u,
          (c) => c.copyWith(
            lastMessage: () => last == null ? null : describeMessage(last),
            lastMessageDate: last?['date'] as int? ?? c.lastMessageDate,
            order: main != null ? _order(main) : null,
            isPinned: main?['is_pinned'] as bool?,
          ),
        );
      case 'updateChatPosition':
        final pos = u['position'] as TdObject;
        if ((pos['list'] as TdObject).type != 'chatListMain') return false;
        return _update(
          u,
          (c) => c.copyWith(
            order: _order(pos),
            isPinned: pos['is_pinned'] as bool? ?? false,
          ),
        );
      case 'updateChatReadInbox':
        return _update(
          u,
          (c) => c.copyWith(unreadCount: u['unread_count'] as int),
        );
      case 'updateChatUnreadMentionCount':
        return _update(
          u,
          (c) =>
              c.copyWith(unreadMentionCount: u['unread_mention_count'] as int),
        );
      default:
        return false;
    }
  }

  bool _update(TdObject u, ChatSummary Function(ChatSummary) change) {
    final id = u['chat_id'] as int;
    final chat = _chats[id];
    if (chat == null) return false;
    _chats[id] = change(chat);
    return true;
  }

  static TdObject? _mainPosition(List? positions) {
    if (positions == null) return null;
    for (final p in positions.cast<TdObject>()) {
      if ((p['list'] as TdObject).type == 'chatListMain') return p;
    }
    return null;
  }

  // TDLib sends int64 values as strings in JSON.
  static int _order(TdObject? position) {
    final raw = position?['order'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  static TdObject? _smallPhoto(TdObject? chatPhotoInfo) =>
      chatPhotoInfo?['small'] as TdObject?;
}

/// Short text for a message in the chat list.
String describeMessage(TdObject message) {
  final content = message['content'] as TdObject;
  String caption(String label) {
    final text = (content['caption'] as TdObject?)?['text'] as String?;
    return text == null || text.isEmpty ? label : '$label, $text';
  }

  return switch (content.type) {
    'messageText' => (content['text'] as TdObject)['text'] as String,
    'messagePhoto' => caption('Фото'),
    'messageVideo' => caption('Видео'),
    'messageDocument' => caption('Файл'),
    'messageAudio' => caption('Аудио'),
    'messageAnimation' => caption('GIF'),
    'messageVoiceNote' => 'Голосовое сообщение',
    'messageVideoNote' => 'Видеосообщение',
    'messageSticker' =>
      'Стикер ${(content['sticker'] as TdObject?)?['emoji'] ?? ''}'.trim(),
    'messageLocation' => 'Геопозиция',
    'messageContact' => 'Контакт',
    'messagePoll' => 'Опрос',
    'messageCall' => 'Звонок',
    _ => 'Сообщение',
  };
}
