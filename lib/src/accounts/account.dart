import 'package:flutter/foundation.dart';

/// A locally known Telegram account. Each one has its own TDLib database
/// directory, so accounts never share caches or files.
@immutable
class Account {
  const Account({
    required this.id,
    this.userId,
    this.displayName,
    this.phoneNumber,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    userId: json['userId'] as int?,
    displayName: json['displayName'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
  );

  /// Local id; also the name of the account's data directory.
  final String id;

  /// Telegram user id, known once the account is authorized.
  final int? userId;
  final String? displayName;
  final String? phoneNumber;

  bool get isAuthorized => userId != null;

  String get label {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (phoneNumber != null && phoneNumber!.isNotEmpty) return '+$phoneNumber';
    return 'Новый аккаунт';
  }

  Account copyWith({int? userId, String? displayName, String? phoneNumber}) =>
      Account(
        id: id,
        userId: userId ?? this.userId,
        displayName: displayName ?? this.displayName,
        phoneNumber: phoneNumber ?? this.phoneNumber,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'displayName': displayName,
    'phoneNumber': phoneNumber,
  };
}
