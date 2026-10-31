import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../ink/ink_core.dart';

const _dpi = 144.0;

Future<ui.Image> _decode(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// PDF sayfalarını görüntüye çevirir, çizimleri üzerine işler ve yeni bir
/// PDF oluşturur. Orijinal dosyaya dokunmaz.
///
/// Not: Sayfalar görüntü olarak yazıldığı için çıktıdaki metinler seçilemez.
Future<void> exportAnnotatedPdf({
  required String srcPath,
  required Map<int, List<InkStroke>> strokes,
  required String outPath,
  bool onlyInked = false,
  int? totalPages,
  void Function(int done, int? total)? onProgress,
}) async {
  final bytes = await File(srcPath).readAsBytes();

  final inkPages = (strokes.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => e.key - 1) // Printing.raster sıfırdan başlar
          .toList()
        ..sort());
  final pages = onlyInked ? inkPages : null;
  final total = onlyInked ? inkPages.length : totalPages;

  final doc = pw.Document();
  var i = 0;
  await for (final r in Printing.raster(bytes, pages: pages, dpi: _dpi)) {
    final pageIndex = pages != null ? pages[i] : i;
    final list = strokes[pageIndex + 1];

    Uint8List png;
    if (list == null || list.isEmpty) {
      png = await r.toPng();
    } else {
      final img = await _decode(r.pixels, r.width, r.height);
      final size = Size(r.width.toDouble(), r.height.toDouble());
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
      canvas.drawImage(img, Offset.zero, Paint());
      paintInk(canvas, size, list);
      final out = await rec.endRecording().toImage(r.width, r.height);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      png = data!.buffer.asUint8List();
    }

    final fmt = PdfPageFormat(r.width * 72 / _dpi, r.height * 72 / _dpi);
    final image = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
    i++;
    onProgress?.call(i, total);
  }

  await File(outPath).writeAsBytes(await doc.save());
}
