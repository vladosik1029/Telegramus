import 'package:flutter_test/flutter_test.dart';
import 'package:telegramus/src/features/chats/chat_list_screen.dart';
import 'package:telegramus/src/features/chats/chat_store.dart';

Map<String, dynamic> _main(String order, {bool pinned = false}) => {
  '@type': 'chatPosition',
  'list': {'@type': 'chatListMain'},
  'order': order,
  'is_pinned': pinned,
};

Map<String, dynamic> _newChat(int id, String title, {String order = '0'}) => {
  '@type': 'updateNewChat',
  'chat': {
    '@type': 'chat',
    'id': id,
    'title': title,
    'positions': [if (order != '0') _main(order)],
    'unread_count': 0,
  },
};

Map<String, dynamic> _text(String text, int date) => {
  '@type': 'message',
  'date': date,
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text},
  },
};

void main() {
  test('sorts chats by main-list order and hides chats outside it', () {
    final store = ChatStore()
      ..apply(_newChat(1, 'A', order: '100'))
      ..apply(_newChat(2, 'B', order: '300'))
      ..apply(_newChat(3, 'Hidden'));
    expect(store.chats.map((c) => c.title), ['B', 'A']);

    store.apply({
      '@type': 'updateChatPosition',
      'chat_id': 1,
      'position': _main('9223372036854775000', pinned: true),
    });
    expect(store.chats.first.title, 'A');
    expect(store.chats.first.isPinned, isTrue);
  });

  test('ignores positions from other chat lists', () {
    final store = ChatStore()..apply(_newChat(1, 'A', order: '100'));
    final changed = store.apply({
      '@type': 'updateChatPosition',
      'chat_id': 1,
      'position': {
        '@type': 'chatPosition',
        'list': {'@type': 'chatListArchive'},
        'order': '0',
      },
    });
    expect(changed, isFalse);
    expect(store.chats, hasLength(1));
  });

  test('tracks last message, unread counters and title', () {
    final store = ChatStore()..apply(_newChat(1, 'A', order: '100'));
    var notified = 0;
    store.addListener(() => notified++);

    store
      ..apply({
        '@type': 'updateChatLastMessage',
        'chat_id': 1,
        'last_message': _text('привет', 1700000000),
        'positions': [_main('500')],
      })
      ..apply({'@type': 'updateChatReadInbox', 'chat_id': 1, 'unread_count': 3})
      ..apply({'@type': 'updateChatTitle', 'chat_id': 1, 'title': 'A2'});

    final chat = store.chats.single;
    expect(chat.lastMessage, 'привет');
    expect(chat.lastMessageDate, 1700000000);
    expect(chat.order, 500);
    expect(chat.unreadCount, 3);
    expect(chat.title, 'A2');
    expect(notified, 3);
  });

  test('updates for unknown chats are ignored', () {
    final store = ChatStore();
    expect(
      store.apply({'@type': 'updateChatTitle', 'chat_id': 42, 'title': 'x'}),
      isFalse,
    );
  });

  test('describes media messages', () {
    expect(
      describeMessage({
        'content': {
          '@type': 'messagePhoto',
          'caption': {'text': 'море'},
        },
      }),
      'Фото, море',
    );
    expect(
      describeMessage({
        'content': {'@type': 'messageVoiceNote'},
      }),
      'Голосовое сообщение',
    );
  });

  test('formats chat dates', () {
    final now = DateTime(2026, 11, 11, 15);
    int ts(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    expect(formatChatDate(ts(DateTime(2026, 11, 11, 9, 5)), now), '09:05');
    expect(formatChatDate(ts(DateTime(2026, 11, 9, 9)), now), 'пн');
    expect(formatChatDate(ts(DateTime(2026, 1, 2)), now), '02.01.26');
  });
}
