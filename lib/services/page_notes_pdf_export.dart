import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing;

import '../ink/ink_core.dart';
import '../models/page_note.dart';

typedef PdfFontLoader = Future<pw.Font> Function();

Future<_PersistentPdfCache>? _fontCacheFuture;

Future<pw.Font> _loadNoteFont({bool bold = false}) async {
  final cache = await (_fontCacheFuture ??= _createFontCache());
  printing.PdfBaseCache.defaultCache = cache;
  final font = bold
      ? await printing.PdfGoogleFonts.notoSansBold()
      : await printing.PdfGoogleFonts.notoSansRegular();
  if (font is! pw.TtfFont) {
    throw StateError(
      'Noto Sans yazı tipi yüklenemedi. İnternet bağlantısını kontrol edip '
      'yeniden deneyin.',
    );
  }
  return font;
}

Future<_PersistentPdfCache> _createFontCache() async {
  final appSupportDirectory = await getApplicationSupportDirectory();
  final cache = _PersistentPdfCache(
    Directory(p.join(appSupportDirectory.path, 'pdf-font-cache')),
  );
  await cache.directory.create(recursive: true);
  return cache;
}

class _PersistentPdfCache extends printing.PdfBaseCache {
  final Directory directory;

  _PersistentPdfCache(this.directory);

  File _fileFor(String key) {
    final safeKey = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File(p.join(directory.path, '$safeKey.bin'));
  }

  @override
  Future<void> add(String key, Uint8List bytes) async {
    await _fileFor(key).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<bool> contains(String key) => _fileFor(key).exists();

  @override
  Future<void> remove(String key) async {
    final file = _fileFor(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Uint8List?> get(String key) async {
    final file = _fileFor(key);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> clear() async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      await entity.delete(recursive: entity is Directory);
    }
  }
}

Future<void> appendPageNotesToPdf(
  pw.Document document,
  Map<String, List<PageNote>> notesByPage, {
  PdfFontLoader? fontLoader,
}) async {
  if (notesByPage.values.every((notes) => notes.isEmpty)) return;

  final loadFont = fontLoader ?? _loadNoteFont;
  final font = await loadFont();
  final boldFont = fontLoader == null ? await _loadNoteFont(bold: true) : font;
  final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
  final entries = notesByPage.entries.toList()..sort(_comparePageKeys);
  for (final entry in entries) {
    final pageLabel = _pageLabel(entry.key);
    for (var index = 0; index < entry.value.length; index++) {
      final note = entry.value[index];
      final drawing = note.strokes.isEmpty
          ? null
          : pw.MemoryImage(await _renderDrawing(note.strokes, note.paperStyle));
      document.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(44, 44, 44, 48),
          build: (_) => [
            pw.Header(level: 0, text: '$pageLabel · Not ${index + 1}'),
            if (note.text.trim().isNotEmpty)
              pw.Paragraph(
                text: note.text,
                style: pw.TextStyle(fontSize: note.fontSize),
              ),
            if (drawing != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 16),
                child: pw.Image(
                  drawing,
                  width: double.infinity,
                  height: 300,
                  fit: pw.BoxFit.contain,
                ),
              ),
          ],
        ),
      );
    }
  }
}

int _comparePageKeys(
  MapEntry<String, List<PageNote>> left,
  MapEntry<String, List<PageNote>> right,
) {
  final leftMatch = RegExp(r'^(.*?)-(\d+)$').firstMatch(left.key);
  final rightMatch = RegExp(r'^(.*?)-(\d+)$').firstMatch(right.key);
  if (leftMatch != null &&
      rightMatch != null &&
      leftMatch.group(1) == rightMatch.group(1)) {
    return int.parse(leftMatch.group(2)!)
        .compareTo(int.parse(rightMatch.group(2)!));
  }
  return left.key.compareTo(right.key);
}

Future<Uint8List> _renderDrawing(
  List<InkStroke> strokes,
  NotePaperStyle paperStyle,
) async {
  const scale = 2.0;
  const logicalSize = Size(595, 842);
  const pixelSize = 1190;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..drawRect(
      Offset.zero & logicalSize,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  const spacing = 24.0;
  final paperPaint = Paint()
    ..color = const Color(0xFFCED5DE)
    ..strokeWidth = 0.7;
  if (paperStyle == NotePaperStyle.grid || paperStyle == NotePaperStyle.lined) {
    if (paperStyle == NotePaperStyle.grid) {
      for (var x = spacing; x < logicalSize.width; x += spacing) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, logicalSize.height),
          paperPaint,
        );
      }
    }
    for (var y = spacing; y < logicalSize.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(logicalSize.width, y), paperPaint);
    }
  } else if (paperStyle == NotePaperStyle.dotted) {
    for (var y = spacing; y < logicalSize.height; y += spacing) {
      for (var x = spacing; x < logicalSize.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paperPaint);
      }
    }
  }
  paintInk(canvas, logicalSize, strokes);
  final image = await recorder.endRecording().toImage(
    pixelSize,
    pixelSize * 842 ~/ 595,
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('Not çizimi PDF için görüntüye dönüştürülemedi.');
  }
  return bytes.buffer.asUint8List();
}

String _pageLabel(String key) {
  final match = RegExp(r'^(?:pdf|slide)-(\d+)$').firstMatch(key);
  if (match != null) return 'Sayfa ${match.group(1)}';
  if (key.startsWith('sheet-')) return 'Çalışma sayfası ${key.substring(6)}';
  return switch (key) {
    'word-1' => 'Word belgesi',
    'note-1' => 'Metin belgesi',
    'image-1' => 'Görsel',
    _ => key,
  };
}

Future<Uint8List> createPageNotesPdf(
  Map<String, List<PageNote>> notesByPage, {
  PdfFontLoader? fontLoader,
}) async {
  final document = pw.Document();
  await appendPageNotesToPdf(document, notesByPage, fontLoader: fontLoader);
  return document.save();
}
