import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ink/ink_core.dart';

/// PDF'in kendisine dokunmadan, çizimleri uygulamanın kendi klasöründe saklar.
class AnnotationStore {
  static Future<File> _file(String pdfPath) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'annotations'));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    var h = 2166136261;
    for (final c in pdfPath.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
    }
    final name = p
        .basenameWithoutExtension(pdfPath)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(dir.path, '${name}_${h.toRadixString(16)}.json'));
  }

  static Future<Map<int, List<InkStroke>>> load(String pdfPath) async {
    final out = <int, List<InkStroke>>{};
    try {
      final f = await _file(pdfPath);
      if (!f.existsSync()) return out;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      (data['pages'] as Map<String, dynamic>).forEach((k, v) {
        out[int.parse(k)] = [
          for (final s in (v as List)) InkStroke.fromJson(s as Map<String, dynamic>),
        ];
      });
    } catch (_) {}
    return out;
  }

  static Future<void> save(String pdfPath, Map<int, List<InkStroke>> strokes) async {
    try {
      final f = await _file(pdfPath);
      final pages = <String, dynamic>{};
      strokes.forEach((page, list) {
        if (list.isNotEmpty) pages['$page'] = [for (final s in list) s.toJson()];
      });
      await f.writeAsString(jsonEncode({'pages': pages}));
    } catch (_) {}
  }
}
