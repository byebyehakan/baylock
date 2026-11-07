import 'dart:typed_data';

import 'package:flutter/material.dart';

class PptxPresentation {
  final double width;
  final double height;
  final List<PptxSlide> slides;

  const PptxPresentation({
    required this.width,
    required this.height,
    required this.slides,
  });
}

class PptxSlide {
  final Color? background;
  final List<PptxElement> elements;

  const PptxSlide({required this.background, required this.elements});
}

class PptxElement {
  final Rect bounds;
  final Color? fill;
  final Color? line;
  final String geometry;
  final List<PptxParagraph> paragraphs;
  final Uint8List? image;
  final EdgeInsets textInsets;
  final bool verticalCenter;

  const PptxElement({
    required this.bounds,
    required this.fill,
    required this.line,
    required this.geometry,
    required this.paragraphs,
    required this.image,
    required this.textInsets,
    required this.verticalCenter,
  });
}

class PptxParagraph {
  final List<PptxTextRun> runs;
  final TextAlign alignment;
  final bool bullet;

  const PptxParagraph({
    required this.runs,
    required this.alignment,
    required this.bullet,
  });
}

class PptxTextRun {
  final String text;
  final Color? color;
  final double? fontSize;
  final bool bold;
  final bool italic;
  final bool underline;

  const PptxTextRun({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.bold,
    required this.italic,
    required this.underline,
  });
}
