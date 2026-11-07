import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/doc_item.dart';

class FileService {
  static const supported = [
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'ppt', 'pptx',
    'odt', 'ods', 'odp', 'rtf', 'txt', 'md', 'png', 'jpg', 'jpeg', 'webp',
    'baylock',
  ];

  /// Uygulamanın kendi klasörü: sadece uygulamada yazdığın notlar ve çizimler.
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

  /// Sistem dosya seçiciyi açar. Dosya kopyalanmaz, seçilen yol döner.
  static Future<String?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: supported,
    );
    return file?.path;
  }

  /// Uygulamada yazılan notlar ve çizimler.
  static Future<List<DocFile>> localFiles() async {
    final dir = await docsDir();
    final out = <DocFile>[];
    for (final e in dir.listSync()) {
      if (e is File) out.add(DocFile.fromPath(e.path));
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }
}
