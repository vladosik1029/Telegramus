import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/accounts_controller.dart';
import '../../tdlib/td_client.dart';

const _palette = [
  Color(0xFFE17076),
  Color(0xFFFAA774),
  Color(0xFFA695E7),
  Color(0xFF7BC862),
  Color(0xFF6EC9CB),
  Color(0xFF65AADD),
  Color(0xFFEE7AAE),
];

/// Round avatar: the TDLib photo of [accountId]'s copy of [file], or
/// initials on a colored background while it loads or if there is none.
class TdAvatar extends ConsumerWidget {
  const TdAvatar({
    super.key,
    required this.accountId,
    required this.title,
    required this.seed,
    this.file,
    this.radius = 24,
  });

  final String accountId;
  final String title;

  /// Stable number (chat or user id) used to pick the placeholder color.
  final int seed;
  final TdObject? file;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = CircleAvatar(
      radius: radius,
      backgroundColor: _palette[seed.abs() % _palette.length],
      child: Text(
        _initials(title),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.75,
        ),
      ),
    );
    final f = file;
    if (f == null) return placeholder;

    final session = ref.watch(sessionProvider(accountId));
    return FutureBuilder<String?>(
      future: session.localPath(f),
      builder: (context, snap) {
        final path = snap.data;
        if (path == null) return placeholder;
        return CircleAvatar(
          radius: radius,
          backgroundImage: FileImage(File(path)),
        );
      },
    );
  }

  static String _initials(String title) {
    final parts = title.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final letters = parts
        .take(2)
        .map((s) => String.fromCharCode(s.runes.first));
    final result = letters.join().toUpperCase();
    return result.isEmpty ? '?' : result;
  }
}
