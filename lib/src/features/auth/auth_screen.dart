import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/accounts_controller.dart';
import '../../accounts/auth_state.dart';
import '../../tdlib/td_client.dart';

/// Login flow for one account: phone → code → (2FA password) → ready.
class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider(accountId));
    final session = ref.watch(sessionProvider(accountId));
    final accounts = ref.watch(accountsProvider).requireValue;
    final canCancel = accounts.accounts.length > 1;

    final Widget body = switch (state) {
      AuthInitializing() ||
      AuthReady() ||
      AuthLoggingOut() ||
      AuthClosed() => const Center(child: CircularProgressIndicator()),
      AuthWaitPhone() => _StepForm(
        key: const ValueKey('phone'),
        title: 'Вход в Telegram',
        subtitle: 'Введите номер телефона в международном формате.',
        fields: const [
          _Field('Номер телефона', hint: '+7 900 000-00-00', phone: true),
        ],
        action: 'Далее',
        onSubmit: (v) => session.submitPhone(v[0]),
      ),
      AuthWaitCode(
        :final phoneNumber,
        :final codeLength,
        :final deliveredViaApp,
      ) =>
        _StepForm(
          key: const ValueKey('code'),
          title: '+$phoneNumber',
          subtitle: deliveredViaApp
              ? 'Код отправлен в приложение Telegram на другом устройстве.'
              : 'Мы отправили код подтверждения.',
          fields: [_Field('Код', digits: true, maxLength: codeLength)],
          action: 'Войти',
          onSubmit: (v) => session.submitCode(v[0]),
        ),
      AuthWaitPassword(:final hint) => _StepForm(
        key: const ValueKey('password'),
        title: 'Облачный пароль',
        subtitle: hint.isEmpty
            ? 'Аккаунт защищён двухэтапной проверкой.'
            : 'Подсказка: $hint',
        fields: const [_Field('Пароль', obscure: true)],
        action: 'Войти',
        onSubmit: (v) => session.submitPassword(v[0]),
      ),
      AuthWaitRegistration() => _StepForm(
        key: const ValueKey('register'),
        title: 'Новый аккаунт',
        subtitle: 'Этот номер ещё не зарегистрирован в Telegram.',
        fields: const [_Field('Имя'), _Field('Фамилия', optional: true)],
        action: 'Зарегистрироваться',
        onSubmit: (v) => session.register(v[0], v[1]),
      ),
      AuthWaitOtherDevice(:final link) => _Info(
        title: 'Подтвердите вход',
        text: 'Откройте ссылку на устройстве, где вы уже вошли:\n$link',
      ),
      AuthUnsupported(:final tdType) => _Info(
        title: 'Шаг пока не поддерживается',
        text: 'TDLib запросил шаг $tdType, его ещё нет в клиенте.',
      ),
    };

    return Scaffold(
      appBar: AppBar(
        leading: canCancel
            ? IconButton(
                tooltip: 'Отменить добавление',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    ref.read(accountsProvider.notifier).cancelLogin(accountId),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class _Field {
  const _Field(
    this.label, {
    this.hint,
    this.phone = false,
    this.digits = false,
    this.obscure = false,
    this.optional = false,
    this.maxLength,
  });

  final String label;
  final String? hint;
  final bool phone;
  final bool digits;
  final bool obscure;
  final bool optional;
  final int? maxLength;
}

class _StepForm extends StatefulWidget {
  const _StepForm({
    super.key,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.action,
    required this.onSubmit,
  });

  final String title;
  final String subtitle;
  final List<_Field> fields;
  final String action;
  final Future<void> Function(List<String> values) onSubmit;

  @override
  State<_StepForm> createState() => _StepFormState();
}

class _StepFormState extends State<_StepForm> {
  late final _controllers = [
    for (final _ in widget.fields) TextEditingController(),
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final values = [for (final c in _controllers) c.text.trim()];
    for (var i = 0; i < values.length; i++) {
      if (values[i].isEmpty && !widget.fields[i].optional) {
        setState(() => _error = 'Заполните поле «${widget.fields[i].label}»');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(values);
    } on TdException catch (e) {
      if (mounted) setState(() => _error = _humanize(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          widget.subtitle,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < widget.fields.length; i++) ...[
          TextField(
            controller: _controllers[i],
            autofocus: i == 0,
            enabled: !_busy,
            obscureText: widget.fields[i].obscure,
            maxLength: widget.fields[i].maxLength,
            keyboardType: widget.fields[i].phone
                ? TextInputType.phone
                : widget.fields[i].digits
                ? TextInputType.number
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: widget.fields[i].label,
              hintText: widget.fields[i].hint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.action),
        ),
      ],
    );
  }

  static String _humanize(TdException e) => switch (e.message) {
    'PHONE_NUMBER_INVALID' => 'Неверный номер телефона',
    'PHONE_CODE_INVALID' => 'Неверный код',
    'PHONE_CODE_EXPIRED' => 'Код устарел, запросите новый',
    'PASSWORD_HASH_INVALID' => 'Неверный пароль',
    _ when e.code == 429 => 'Слишком много попыток, попробуйте позже',
    _ => e.message,
  };
}

class _Info extends StatelessWidget {
  const _Info({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      SelectableText(text, textAlign: TextAlign.center),
    ],
  );
}
