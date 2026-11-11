import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'account.dart';

class StoredAccounts {
  const StoredAccounts(this.accounts, this.activeId);
  final List<Account> accounts;
  final String? activeId;
}

/// Persists the account list in `<app support>/accounts.json` and hands out
/// a separate data directory per account: `<app support>/accounts/<id>/`.
class AccountRepository {
  AccountRepository(this.rootDir);

  static Future<AccountRepository> create() async {
    final dir = await getApplicationSupportDirectory();
    return AccountRepository(dir.path);
  }

  final String rootDir;

  File get _file => File(p.join(rootDir, 'accounts.json'));

  String dataDirFor(String accountId) => p.join(rootDir, 'accounts', accountId);

  Future<StoredAccounts> load() async {
    if (!await _file.exists()) return const StoredAccounts([], null);
    try {
      final json = jsonDecode(await _file.readAsString()) as Map;
      final list = (json['accounts'] as List)
          .map((e) => Account.fromJson((e as Map).cast()))
          .toList();
      return StoredAccounts(list, json['activeId'] as String?);
    } on FormatException {
      return const StoredAccounts([], null);
    }
  }

  Future<void> save(List<Account> accounts, String? activeId) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'activeId': activeId,
        'accounts': accounts.map((a) => a.toJson()).toList(),
      }),
    );
    await tmp.rename(_file.path);
  }

  Future<void> deleteData(String accountId) async {
    final dir = Directory(dataDirFor(accountId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  String newAccountId() =>
      'acc_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
