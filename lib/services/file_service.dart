import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/doc_item.dart';

class FileService {
  static const supported = [
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'ppt', 'pptx',
    'odt', 'ods', 'odp', 'rtf', 'txt', 'md', 'png', 'jpg', 'jpeg', 'webp',
  ];

  /// Uygulamanın kendi belge klasörü (notlar, çizimler, içe aktarılanlar).
  static Future<Directory> docsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'Belgelerim'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<String> uniquePath(String dir, String fileName) async {
    final name = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var candidate = p.join(dir, fileName);
    var i = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir, '$name ($i)$ext');
      i++;
    }
    return candidate;
  }

  /// Sistem dosya seçiciyi açar, seçilen dosyayı Belgelerim'e kopyalar.
  static Future<String?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: supported,
    );
    final src = file?.path;
    if (src == null) return null;
    final dir = await docsDir();
    if (p.isWithin(dir.path, src)) return src;
    final dest = await uniquePath(dir.path, p.basename(src));
    await File(src).copy(dest);
    return dest;
  }

  static Future<List<DocFile>> localFiles() async {
    final dir = await docsDir();
    final out = <DocFile>[];
    for (final e in dir.listSync()) {
      if (e is File) out.add(DocFile.fromPath(e.path));
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  /// Android'de İndirilenler ve Belgeler klasörlerini tarar.
  /// Tüm dosyalara erişim izni ister. iOS'ta sadece uygulama klasörü taranır.
  static Future<List<DocFile>> deviceScan() async {
    final roots = <Directory>[await docsDir()];
    if (Platform.isAndroid) {
      final st = await Permission.manageExternalStorage.request();
      if (st.isGranted) {
        for (final n in ['Download', 'Documents']) {
          roots.add(Directory('/storage/emulated/0/$n'));
        }
      }
    }
    final out = <DocFile>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      try {
        await for (final e in root
            .list(recursive: true, followLinks: false)
            .handleError((_) {})) {
          if (e is File && kindOf(e.path) != DocKind.other) {
            out.add(DocFile.fromPath(e.path));
            if (out.length >= 800) break;
          }
        }
      } catch (_) {}
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }
}