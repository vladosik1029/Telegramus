import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration.
///
/// Values come from `--dart-define` / `--dart-define-from-file`, so the
/// Telegram API credentials never live in the repository. See README.
class AppConfig {
  const AppConfig({
    required this.apiId,
    required this.apiHash,
    this.useTestDc = false,
    this.applicationVersion = '0.1.0',
  });

  factory AppConfig.fromEnvironment() {
    const rawId = String.fromEnvironment('TELEGRAM_API_ID');
    const hash = String.fromEnvironment('TELEGRAM_API_HASH');
    const testDc = String.fromEnvironment('TELEGRAM_USE_TEST_DC');
    return AppConfig(
      apiId: int.tryParse(rawId) ?? 0,
      apiHash: hash,
      useTestDc: testDc.toLowerCase() == 'true',
    );
  }

  final int apiId;
  final String apiHash;
  final bool useTestDc;
  final String applicationVersion;

  bool get isValid => apiId > 0 && apiHash.length >= 16;
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
