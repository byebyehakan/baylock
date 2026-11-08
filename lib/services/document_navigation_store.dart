import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DocumentNavigationStore {
  const DocumentNavigationStore();

  String _key(String path) {
    var hash = 2166136261;
    for (final codeUnit in path.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0xFFFFFFFF;
    }
    return 'document_navigation_${hash.toRadixString(16)}';
  }

  Future<int?> lastPage(String path) async {
    final data = await _read(path);
    final page = data['lastPage'];
    return page is int && page > 0 ? page : null;
  }

  Future<void> saveLastPage(String path, int page) async {
    if (page < 1) return;
    final data = await _read(path);
    data['lastPage'] = page;
    await _write(path, data);
  }

  Future<List<int>> bookmarks(String path) async {
    final value = (await _read(path))['bookmarks'];
    if (value is! List) return [];
    return value.whereType<int>().where((page) => page > 0).toSet().toList()
      ..sort();
  }

  Future<bool> toggleBookmark(String path, int page) async {
    if (page < 1) return false;
    final data = await _read(path);
    final raw = data['bookmarks'];
    final pages = raw is List
        ? raw.whereType<int>().where((value) => value > 0).toSet()
        : <int>{};
    final added = pages.add(page);
    if (!added) pages.remove(page);
    data['bookmarks'] = pages.toList()..sort();
    await _write(path, data);
    return added;
  }

  Future<Map<String, dynamic>> _read(String path) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key(path));
    if (encoded == null) return <String, dynamic>{};
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Belge gezinme verisi geçersiz.');
    }
    return decoded;
  }

  Future<void> _write(String path, Map<String, dynamic> data) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(path), jsonEncode(data));
  }
}
