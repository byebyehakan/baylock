import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/page_note.dart';

class PageNotesStore {
  final Directory? baseDirectory;

  const PageNotesStore({this.baseDirectory});

  Future<List<PageNote>> load(String documentPath, String pageKey) async {
    final file = await _file(documentPath, pageKey);
    if (!await file.exists()) return [];
    await _registerPageKey(documentPath, pageKey);
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      throw const FormatException('Not defteri dosyası geçersiz.');
    }
    return [
      for (final entry in decoded)
        PageNote.fromJson(entry as Map<String, dynamic>),
    ];
  }

  Future<void> save(
    String documentPath,
    String pageKey,
    List<PageNote> notes,
  ) async {
    final file = await _file(documentPath, pageKey);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode([for (final note in notes) note.toJson()]),
      flush: true,
    );
    await _registerPageKey(documentPath, pageKey);
  }

  Future<List<String>> pageKeys(String documentPath) async {
    final file = await _indexFile(documentPath);
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List || decoded.any((key) => key is! String)) {
      throw const FormatException('Not sayfası dizini geçersiz.');
    }
    return decoded.cast<String>();
  }

  Future<Map<String, List<PageNote>>> loadAll(
    String documentPath, {
    Iterable<String> legacyPageKeys = const [],
  }) async {
    final result = <String, List<PageNote>>{};
    final keys = await pageKeys(documentPath);
    for (final key in keys) {
      result[key] = await load(documentPath, key);
    }
    final migrationFlag = await _legacyMigrationFile(documentPath);
    if (await migrationFlag.exists()) return result;

    final base = await _baseDirectory();
    final noteDirectory = Directory(p.join(base.path, 'page_notes'));
    final existingFileNames = await noteDirectory.exists()
        ? (await noteDirectory.list().toList())
            .whereType<File>()
            .map((file) => p.basename(file.path))
            .toSet()
        : <String>{};
    final candidates = legacyPageKeys.toSet().difference(keys.toSet());
    final migratedKeys = [...keys];
    for (final key in candidates) {
      final file = _fileAtBase(base, documentPath, key);
      if (!existingFileNames.contains(p.basename(file.path))) continue;
      result[key] = _decodeNotes(await file.readAsString());
      migratedKeys.add(key);
    }
    if (migratedKeys.length != keys.length) {
      final index = await _indexFile(documentPath);
      await index.parent.create(recursive: true);
      await index.writeAsString(jsonEncode(migratedKeys), flush: true);
    }
    if (legacyPageKeys.isNotEmpty) {
      await migrationFlag.parent.create(recursive: true);
      await migrationFlag.writeAsString('true', flush: true);
    }
    return result;
  }

  Future<File> _legacyMigrationFile(String documentPath) async {
    final base = await _baseDirectory();
    return File(
      p.join(
        base.path,
        'page_notes',
        '${_documentName(documentPath)}_${_hash(documentPath).toRadixString(16)}_legacy.json',
      ),
    );
  }

  Future<void> replaceAll(
    String documentPath,
    Map<String, List<PageNote>> notesByPage,
  ) async {
    final keys = notesByPage.keys.toList();
    for (final entry in notesByPage.entries) {
      final file = await _file(documentPath, entry.key);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode([for (final note in entry.value) note.toJson()]),
        flush: true,
      );
    }
    final index = await _indexFile(documentPath);
    await index.parent.create(recursive: true);
    await index.writeAsString(jsonEncode(keys), flush: true);
    final migrationFlag = await _legacyMigrationFile(documentPath);
    await migrationFlag.writeAsString('true', flush: true);
  }

  Future<File> _indexFile(String documentPath) async {
    final base = await _baseDirectory();
    return File(
      p.join(
        base.path,
        'page_notes',
        '${_documentName(documentPath)}_${_hash(documentPath).toRadixString(16)}_index.json',
      ),
    );
  }

  Future<void> _registerPageKey(String documentPath, String pageKey) async {
    final keys = await pageKeys(documentPath);
    if (keys.contains(pageKey)) return;
    final file = await _indexFile(documentPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([...keys, pageKey]), flush: true);
  }

  Future<File> _file(String documentPath, String pageKey) async {
    final base = await _baseDirectory();
    return _fileAtBase(base, documentPath, pageKey);
  }

  File _fileAtBase(Directory base, String documentPath, String pageKey) {
    final hash = _hash('$documentPath\u0000$pageKey');
    final name = _documentName(documentPath);
    return File(
      p.join(base.path, 'page_notes', '${name}_${hash.toRadixString(16)}.json'),
    );
  }

  Future<Directory> _baseDirectory() async =>
      baseDirectory ?? await getApplicationSupportDirectory();

  List<PageNote> _decodeNotes(String contents) {
    final decoded = jsonDecode(contents);
    if (decoded is! List) {
      throw const FormatException('Not defteri dosyası geçersiz.');
    }
    return [
      for (final entry in decoded)
        PageNote.fromJson(entry as Map<String, dynamic>),
    ];
  }

  int _hash(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }

  String _documentName(String documentPath) => p
      .basenameWithoutExtension(documentPath)
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
