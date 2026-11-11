import '../tdlib/td_client.dart';

/// App-level view of TDLib's `AuthorizationState`.
sealed class AuthState {
  const AuthState();

  factory AuthState.fromTd(TdObject s) {
    switch (s.type) {
      case 'authorizationStateWaitPhoneNumber':
        return const AuthWaitPhone();
      case 'authorizationStateWaitCode':
        final info = s['code_info'] as TdObject;
        final codeType = info['type'] as TdObject;
        return AuthWaitCode(
          phoneNumber: info['phone_number'] as String? ?? '',
          codeLength: codeType['length'] as int?,
          deliveredViaApp:
              codeType.type == 'authenticationCodeTypeTelegramMessage',
        );
      case 'authorizationStateWaitPassword':
        return AuthWaitPassword(
          hint: s['password_hint'] as String? ?? '',
          hasRecoveryEmail: s['has_recovery_email_address'] as bool? ?? false,
        );
      case 'authorizationStateWaitRegistration':
        return const AuthWaitRegistration();
      case 'authorizationStateWaitOtherDeviceConfirmation':
        return AuthWaitOtherDevice(s['link'] as String? ?? '');
      case 'authorizationStateReady':
        return const AuthReady();
      case 'authorizationStateLoggingOut':
        return const AuthLoggingOut();
      case 'authorizationStateClosing':
      case 'authorizationStateClosed':
        return const AuthClosed();
      case 'authorizationStateWaitTdlibParameters':
        return const AuthInitializing();
      default:
        // e.g. authorizationStateWaitEmailAddress / WaitEmailCode /
        // WaitPremiumPurchase: not implemented in the skeleton yet.
        return AuthUnsupported(s.type);
    }
  }
}

class AuthInitializing extends AuthState {
  const AuthInitializing();
}

class AuthWaitPhone extends AuthState {
  const AuthWaitPhone();
}

class AuthWaitCode extends AuthState {
  const AuthWaitCode({
    required this.phoneNumber,
    required this.codeLength,
    required this.deliveredViaApp,
  });
  final String phoneNumber;
  final int? codeLength;
  final bool deliveredViaApp;
}

class AuthWaitPassword extends AuthState {
  const AuthWaitPassword({required this.hint, required this.hasRecoveryEmail});
  final String hint;
  final bool hasRecoveryEmail;
}

class AuthWaitRegistration extends AuthState {
  const AuthWaitRegistration();
}

class AuthWaitOtherDevice extends AuthState {
  const AuthWaitOtherDevice(this.link);
  final String link;
}

class AuthReady extends AuthState {
  const AuthReady();
}

class AuthLoggingOut extends AuthState {
  const AuthLoggingOut();
}

class AuthClosed extends AuthState {
  const AuthClosed();
}

class AuthUnsupported extends AuthState {
  const AuthUnsupported(this.tdType);
  final String tdType;
}
