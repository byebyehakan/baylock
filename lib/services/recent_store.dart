import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class RecentStore {
  static const _key = 'recent_files';

  static Future<List<String>> load() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_key) ?? [];
    return list.where((e) => File(e).existsSync()).toList();
  }

  static Future<void> add(String path) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_key) ?? [];
    list.remove(path);
    list.insert(0, path);
    await sp.setStringList(_key, list.take(50).toList());
  }

  static Future<void> remove(String path) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_key) ?? [];
    list.remove(path);
    await sp.setStringList(_key, list);
  }
}
