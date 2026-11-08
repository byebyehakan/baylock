import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../models/pptx_presentation.dart';

class PptxService {
  static const _designWidth = 960.0;
  static const _backgroundParseThreshold = 256 * 1024;

  static Future<PptxPresentation> load(String path) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length >= _backgroundParseThreshold) {
      return Isolate.run(() => _parse(bytes));
    }
    return _parse(bytes);
  }

  static PptxPresentation _parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final themeColors = _readThemeColors(archive);
    final presentation = XmlDocument.parse(
      _xml(archive, 'ppt/presentation.xml'),
    );
    final size = _first(presentation.rootElement, 'p:sldSz');
    final width = double.tryParse(size?.getAttribute('cx') ?? '') ?? 12192000;
    final height = double.tryParse(size?.getAttribute('cy') ?? '') ?? 6858000;
    if (width <= 0 || height <= 0) {
      throw const FormatException('Sunum boyutları geçersiz.');
    }
    final slides = <PptxSlide>[];

    final slidePaths = _slideOrder(archive, presentation);
    for (final slidePath in slidePaths) {
      slides.add(_readSlide(archive, slidePath, width, height, themeColors));
    }
    if (slides.isEmpty)
      throw const FormatException('Sunumda slayt bulunamadı.');

    return PptxPresentation(width: width, height: height, slides: slides);
  }

  static List<String> _slideOrder(Archive archive, XmlDocument presentation) {
    final relationships = _relationships(
      archive,
      'ppt/_rels/presentation.xml.rels',
    );
    final ids = presentation.rootElement
        .findAllElements('p:sldId')
        .map((element) => element.getAttribute('r:id'))
        .whereType<String>();
    final ordered = [
      for (final id in ids)
        if (relationships[id] != null)
          _resolveTarget('ppt', relationships[id]!),
    ];
    if (ordered.isNotEmpty) return ordered;

    final pattern = RegExp(r'^ppt/slides/slide(\d+)\.xml$');
    final paths =
        archive.files
            .map((file) => file.name)
            .where((name) => pattern.hasMatch(name))
            .toList()
          ..sort(
            (a, b) =>
                int.parse(pattern.firstMatch(a)!.group(1)!)
                    .compareTo(int.parse(pattern.firstMatch(b)!.group(1)!)),
          );
    return paths;
  }

  static PptxSlide _readSlide(
    Archive archive,
    String path,
    double slideWidth,
    double slideHeight,
    Map<String, Color> themeColors,
  ) {
    final doc = XmlDocument.parse(_xml(archive, path));
    final scaleX = _designWidth / slideWidth;
    final designHeight = slideHeight * scaleX;
    final scaleY = designHeight / slideHeight;
    final slideNode = doc.rootElement;
    final background = _readBackground(slideNode, themeColors);
    final relationships = _relationships(
      archive,
      '${p.posix.dirname(path)}/_rels/${p.posix.basename(path)}.rels',
    );
    final tree = _first(_first(slideNode, 'p:cSld'), 'p:spTree');
    final elements = <PptxElement>[];

    if (tree != null) {
      for (final node in tree.children.whereType<XmlElement>()) {
        if (_localName(node) == 'sp') {
          elements.add(_readShape(node, scaleX, scaleY, themeColors));
        } else if (_localName(node) == 'pic') {
          final image = _readPicture(archive, node, relationships, path);
          if (image != null) {
            elements.add(
              _readShape(node, scaleX, scaleY, themeColors, image: image),
            );
          }
        }
      }
    }
    return PptxSlide(background: background, elements: elements);
  }

  static PptxElement _readShape(
    XmlElement node,
    double scaleX,
    double scaleY,
    Map<String, Color> themeColors, {
    Uint8List? image,
  }) {
    final properties = _first(node, 'p:spPr');
    final transform = _first(properties, 'a:xfrm');
    final offset = _first(transform, 'a:off');
    final extent = _first(transform, 'a:ext');
    final x = _number(offset, 'x') * scaleX;
    final y = _number(offset, 'y') * scaleY;
    final width = _number(extent, 'cx') * scaleX;
    final height = _number(extent, 'cy') * scaleY;

    final preset = _first(properties, 'a:prstGeom')?.getAttribute('prst') ?? '';
    final fill = _readColor(_first(properties, 'a:solidFill'), themeColors);
    final lineNode = _first(properties, 'a:ln');
    final line = _readColor(_first(lineNode, 'a:solidFill'), themeColors);
    final body = _first(node, 'p:txBody');
    final bodyProperties = _first(body, 'a:bodyPr');
    final paragraphs = <PptxParagraph>[];

    if (body != null) {
      for (final paragraph in body.findElements('a:p')) {
        final paragraphProperties = _first(paragraph, 'a:pPr');
        final runs = <PptxTextRun>[];
        for (final run in paragraph.children.whereType<XmlElement>()) {
          final runName = _localName(run);
          if (runName != 'r' && runName != 'fld') continue;
          final text = _first(run, 'a:t')?.innerText ?? '';
          if (text.isEmpty) continue;
          final style =
              _first(run, 'a:rPr') ??
              _first(paragraphProperties, 'a:defRPr') ??
              _first(paragraph, 'a:endParaRPr');
          runs.add(_readRun(text, style, themeColors));
        }
        if (runs.isNotEmpty) {
          final bullet =
              _first(paragraphProperties, 'a:buChar') != null ||
              _first(paragraphProperties, 'a:buAutoNum') != null;
          paragraphs.add(
            PptxParagraph(
              runs: runs,
              alignment: _alignment(paragraphProperties?.getAttribute('algn')),
              bullet: bullet,
            ),
          );
        }
      }
    }

    return PptxElement(
      bounds: Rect.fromLTWH(x, y, width, height),
      fill: fill,
      line: line,
      geometry: preset,
      paragraphs: paragraphs,
      image: image,
      textInsets: EdgeInsets.fromLTRB(
        _number(bodyProperties, 'lIns') * scaleX,
        _number(bodyProperties, 'tIns') * scaleY,
        _number(bodyProperties, 'rIns') * scaleX,
        _number(bodyProperties, 'bIns') * scaleY,
      ),
      verticalCenter: bodyProperties?.getAttribute('anchor') == 'ctr',
    );
  }

  static PptxTextRun _readRun(
    String text,
    XmlElement? style,
    Map<String, Color> themeColors,
  ) {
    final size = double.tryParse(style?.getAttribute('sz') ?? '');
    return PptxTextRun(
      text: text,
      color: _readColor(_first(style, 'a:solidFill'), themeColors),
      fontSize: size == null ? null : size / 100,
      bold:
          style?.getAttribute('b') == '1' || style?.getAttribute('b') == 'true',
      italic:
          style?.getAttribute('i') == '1' || style?.getAttribute('i') == 'true',
      underline:
          style?.getAttribute('u') != null &&
          style?.getAttribute('u') != 'none',
    );
  }

  static Uint8List? _readPicture(
    Archive archive,
    XmlElement picture,
    Map<String, String> relationships,
    String slidePath,
  ) {
    final blip = _descendant(picture, 'a:blip');
    final embed = blip?.getAttribute('r:embed');
    final target = embed == null ? null : relationships[embed];
    if (target == null) return null;
    final imagePath = _resolveTarget(p.posix.dirname(slidePath), target);
    final file = archive.findFile(imagePath);
    if (file == null) return null;
    return Uint8List.fromList(file.content as List<int>);
  }

  static Color? _readBackground(
    XmlElement slide,
    Map<String, Color> themeColors,
  ) {
    final background = _first(_first(slide, 'p:cSld'), 'p:bg');
    return _readColor(
      _first(_first(background, 'p:bgPr'), 'a:solidFill'),
      themeColors,
    );
  }

  static Map<String, Color> _readThemeColors(Archive archive) {
    final theme = archive.findFile('ppt/theme/theme1.xml');
    if (theme == null) return {};
    final doc = XmlDocument.parse(utf8.decode(theme.content as List<int>));
    final scheme = _first(doc.rootElement, 'a:clrScheme');
    if (scheme == null) return {};
    final colors = <String, Color>{};
    for (final entry in scheme.children.whereType<XmlElement>()) {
      final color = _readColor(entry, const {});
      if (color != null) colors[_localName(entry)] = color;
    }
    return colors;
  }

  static Color? _readColor(XmlElement? parent, Map<String, Color> themeColors) {
    if (parent == null) return null;
    final colorNode = parent.children.whereType<XmlElement>().firstOrNull;
    if (colorNode == null) return null;
    final value =
        colorNode.getAttribute('val') ?? colorNode.getAttribute('lastClr');
    if (_localName(colorNode) == 'schemeClr') {
      return themeColors[value ?? ''];
    }
    if (value == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value))
      return null;
    return Color(0xFF000000 | int.parse(value, radix: 16));
  }

  static Map<String, String> _relationships(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return {};
    final doc = XmlDocument.parse(utf8.decode(file.content as List<int>));
    return {
      for (final relation in doc.findAllElements('Relationship'))
        if (relation.getAttribute('Id') != null &&
            relation.getAttribute('Target') != null)
          relation.getAttribute('Id')!: relation.getAttribute('Target')!,
    };
  }

  static String _resolveTarget(String base, String target) {
    if (target.startsWith('/')) return target.substring(1);
    return p.posix.normalize(p.posix.join(base, target));
  }

  static String _xml(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) throw FormatException('$path bulunamadı.');
    return utf8.decode(file.content as List<int>);
  }

  static XmlElement? _first(XmlElement? parent, String name) {
    if (parent == null) return null;
    final elements = parent.findElements(name);
    return elements.isEmpty ? null : elements.first;
  }

  static XmlElement? _descendant(XmlElement? parent, String name) {
    if (parent == null) return null;
    final elements = parent.findAllElements(name);
    return elements.isEmpty ? null : elements.first;
  }

  static String _localName(XmlElement element) => element.name.local;

  static double _number(XmlElement? element, String attribute) =>
      double.tryParse(element?.getAttribute(attribute) ?? '') ?? 0;

  static TextAlign _alignment(String? value) => switch (value) {
    'ctr' => TextAlign.center,
    'r' => TextAlign.right,
    'just' => TextAlign.justify,
    _ => TextAlign.left,
  };
}
