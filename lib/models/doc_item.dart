import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

enum DocKind { pdf, word, sheet, slides, text, image, other }

class KindInfo {
  final String label;
  final Color color;
  final IconData icon;
  const KindInfo(this.label, this.color, this.icon);
}

const kindInfo = <DocKind, KindInfo>{
  DocKind.pdf: KindInfo('PDF', Color(0xFFD64545), Icons.picture_as_pdf_rounded),
  DocKind.word: KindInfo('Word', Color(0xFF2B6CB0), Icons.description_rounded),
  DocKind.sheet: KindInfo('Excel', Color(0xFF2F855A), Icons.grid_on_rounded),
  DocKind.slides: KindInfo('Sunum', Color(0xFFDD6B20), Icons.slideshow_rounded),
  DocKind.text: KindInfo('Not', Color(0xFF5A6B7F), Icons.notes_rounded),
  DocKind.image: KindInfo('Görsel', Color(0xFF7B5EA7), Icons.image_rounded),
  DocKind.other: KindInfo('Diğer', Color(0xFF7A8594), Icons.insert_drive_file_rounded),
};

DocKind kindOf(String path) {
  final e = p.extension(path).toLowerCase().replaceFirst('.', '');
  switch (e) {
    case 'pdf':
      return DocKind.pdf;
    case 'doc':
    case 'docx':
    case 'odt':
    case 'rtf':
      return DocKind.word;
    case 'xls':
    case 'xlsx':
    case 'csv':
    case 'ods':
      return DocKind.sheet;
    case 'ppt':
    case 'pptx':
    case 'odp':
      return DocKind.slides;
    case 'txt':
    case 'md':
      return DocKind.text;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'webp':
    case 'gif':
    case 'bmp':
      return DocKind.image;
    default:
      return DocKind.other;
  }
}

class DocFile {
  final String path;
  final String name;
  final DateTime modified;
  final int size;
  final DocKind kind;

  const DocFile({
    required this.path,
    required this.name,
    required this.modified,
    required this.size,
    required this.kind,
  });

  factory DocFile.fromPath(String path) {
    var m = DateTime.fromMillisecondsSinceEpoch(0);
    var s = 0;
    try {
      final st = File(path).statSync();
      m = st.modified;
      s = st.size;
    } catch (_) {}
    return DocFile(
      path: path,
      name: p.basename(path),
      modified: m,
      size: s,
      kind: kindOf(path),
    );
  }

  String get ext => p.extension(path).replaceFirst('.', '').toUpperCase();
}
