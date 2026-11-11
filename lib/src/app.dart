import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accounts/accounts_controller.dart';
import 'config/app_config.dart';
import 'features/accounts/account_home.dart';
import 'features/common/status_screens.dart';

class TelegramusApp extends StatelessWidget {
  const TelegramusApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5B6CFF),
        brightness: b,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Telegramus',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appConfigProvider).isValid) {
      return const MessageScreen(
        icon: Icons.key_off_outlined,
        title: 'Нет api_id / api_hash',
        message:
            'Получите ключи на https://my.telegram.org, скопируйте '
            'config/telegram.example.json в config/telegram.json и '
            'запустите:\nflutter run --dart-define-from-file=config/telegram.json',
      );
    }
    return switch (ref.watch(accountsProvider)) {
      AsyncData() => const AccountShell(),
      AsyncError(:final error) => MessageScreen(
        icon: Icons.error_outline,
        title: 'Не удалось запустить TDLib',
        message:
            '$error\n\nПроверьте, что библиотека tdjson собрана и лежит '
            'рядом с приложением (см. README), или укажите путь в '
            'переменной окружения TDJSON_PATH.',
      ),
      _ => const SplashScreen(),
    };
  }
}
