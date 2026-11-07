import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

import '../ink/ink_core.dart';
import '../models/page_note.dart';
import 'annotation_store.dart';
import 'file_service.dart';
import 'page_notes_store.dart';

class PageNotesBundleService {
  static const _format = 'baylock-document';
  static const _version = 1;

  final PageNotesStore notesStore;
  final Directory? importDirectory;

  const PageNotesBundleService({
    this.notesStore = const PageNotesStore(),
    this.importDirectory,
  });

  Future<Uint8List> createPackage(String documentPath) async {
    final source = File(documentPath);
    if (!await source.exists()) {
      throw FileSystemException('Belge bulunamadı', documentPath);
    }

    final notes = await notesStore.loadAll(
      documentPath,
      legacyPageKeys: await _legacyPageKeys(source),
    );
    final annotationStrokes = await AnnotationStore.load(documentPath);
    final originalName = p.basename(documentPath);
    final sourceBytes = await source.readAsBytes();
    final archive = Archive()
      ..addFile(ArchiveFile('document/$originalName', sourceBytes.length, sourceBytes))
      ..addFile(
        _jsonFile('baylock.json', {
          'format': _format,
          'version': _version,
          'document': originalName,
          'pageNotes': {
            for (final entry in notes.entries)
              entry.key: [for (final note in entry.value) note.toJson()],
          },
          'annotations': {
            for (final entry in annotationStrokes.entries)
              if (entry.value.isNotEmpty)
                '${entry.key}': [
                  for (final stroke in entry.value) stroke.toJson(),
                ],
          },
        }),
      );
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) {
      throw const FormatException('Paylaşım paketi oluşturulamadı.');
    }
    return Uint8List.fromList(bytes);
  }

  Future<Iterable<String>> _legacyPageKeys(File source) async {
    final extension = p.extension(source.path).toLowerCase();
    if (extension == '.pdf') {
      return [for (var page = 1; page <= 2000; page++) 'pdf-$page'];
    }
    if (extension == '.pptx') {
      return [for (var slide = 1; slide <= 2000; slide++) 'slide-$slide'];
    }
    if (extension == '.docx') return const ['word-1'];
    if (extension == '.txt' || extension == '.md') return const ['note-1'];
    if ({'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'}
        .contains(extension)) {
      return const ['image-1'];
    }
    if (extension == '.csv') return const ['sheet-CSV'];
    if (extension == '.xlsx') {
      final excel = Excel.decodeBytes(await source.readAsBytes());
      return [for (final name in excel.tables.keys) 'sheet-$name'];
    }
    return const [];
  }

  Future<String> importPackage(String packagePath) async {
    final archive = ZipDecoder().decodeBytes(await File(packagePath).readAsBytes());
    final manifestFile = archive.findFile('baylock.json');
    if (manifestFile == null) {
      throw const FormatException('Baylock paketi tanınamadı.');
    }
    final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>));
    if (manifest is! Map<String, dynamic> ||
        manifest['format'] != _format ||
        manifest['version'] != _version ||
        manifest['document'] is! String) {
      throw const FormatException('Baylock paketi geçersiz veya uyumsuz.');
    }

    final originalName = manifest['document'] as String;
    if (originalName.isEmpty ||
        p.basename(originalName) != originalName ||
        originalName.contains('/') ||
        originalName.contains('\\')) {
      throw const FormatException('Paket içindeki dosya adı geçersiz.');
    }
    final documentEntry = archive.findFile('document/$originalName');
    if (documentEntry == null) {
      throw const FormatException('Paketin içindeki belge bulunamadı.');
    }

    final notesByPage = _readPageNotes(manifest['pageNotes']);
    final annotations = _readAnnotations(manifest['annotations']);
    final destinationDirectory =
        importDirectory ?? await FileService.docsDir();
    await destinationDirectory.create(recursive: true);
    final destination = await FileService.uniquePath(
      destinationDirectory.path,
      originalName,
    );
    await File(destination).writeAsBytes(
      documentEntry.content as List<int>,
      flush: true,
    );
    try {
      await notesStore.replaceAll(destination, notesByPage);
      await AnnotationStore.save(destination, annotations);
    } catch (_) {
      await File(destination).delete();
      rethrow;
    }
    return destination;
  }

  Map<String, List<PageNote>> _readPageNotes(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Paketin sayfa notları geçersiz.');
    }
    final result = <String, List<PageNote>>{};
    value.forEach((key, notes) {
      if (notes is! List) {
        throw const FormatException('Paketin not sayfası geçersiz.');
      }
      result[key] = [
        for (final note in notes)
          PageNote.fromJson(note as Map<String, dynamic>),
      ];
    });
    return result;
  }

  Map<int, List<InkStroke>> _readAnnotations(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Paketin çizimleri geçersiz.');
    }
    final result = <int, List<InkStroke>>{};
    value.forEach((page, strokes) {
      final pageNumber = int.tryParse(page);
      if (pageNumber == null || pageNumber < 1 || strokes is! List) {
        throw const FormatException('Paketin çizim sayfası geçersiz.');
      }
      result[pageNumber] = [
        for (final stroke in strokes)
          InkStroke.fromJson(stroke as Map<String, dynamic>),
      ];
    });
    return result;
  }

  ArchiveFile _jsonFile(String name, Map<String, Object?> data) {
    final bytes = utf8.encode(jsonEncode(data));
    return ArchiveFile(name, bytes.length, bytes);
  }
}
