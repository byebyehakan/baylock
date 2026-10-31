import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/doc_item.dart';

/// Cihaz hafızasındaki belgelerin diske kaydedilen dizini.
///
/// Hız için:
///  1. Açılışta önce önbellekteki liste anında gösterilir.
///  2. Tarama ayrı bir isolate'ta yapılır, arayüz donmaz.
///  3. Değişmemiş klasörler (klasör değişiklik tarihi aynıysa) yeniden
///     okunmaz, önbellekteki içerik kullanılır.
///  4. Android/, DCIM, Music gibi belge barındırmayan klasörler atlanır.
class DeviceIndex {
  static const _root = '/storage/emulated/0';

  static const _exts = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'ppt', 'pptx',
    'odt', 'ods', 'odp', 'rtf', 'txt', 'md',
  };

  static const _skipDirs = {
    'android', 'dcim', 'movies', 'music', 'pictures', 'ringtones',
    'notifications', 'alarms', 'podcasts', 'audiobooks', 'lost.dir',
    'cache', 'thumbnails',
  };

  static Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'device_index.json'));
  }

  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return true;
    return Permission.manageExternalStorage.isGranted;
  }

  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    final st = await Permission.manageExternalStorage.request();
    return st.isGranted;
  }

  /// Önbellekteki listeyi hemen döndürür (tarama yapmaz).
  static Future<List<DocFile>> loadCached() async {
    try {
      final f = await _cacheFile();
      if (!f.existsSync()) return [];
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return _flatten(data);
    } catch (_) {
      return [];
    }
  }

  /// Cihazı (değişen klasörleri) tarar, önbelleği günceller.
  static Future<List<DocFile>> refresh() async {
    if (!Platform.isAndroid) return [];
    final f = await _cacheFile();
    var old = <String, dynamic>{};
    try {
      if (f.existsSync()) {
        old = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}

    final result = await Isolate.run(() => _scan(old));
    await f.writeAsString(jsonEncode(result));
    return _flatten(result);
  }

  static List<DocFile> _flatten(Map<String, dynamic> data) {
    final out = <DocFile>[];
    final dirs = (data['dirs'] as Map?) ?? {};
    dirs.forEach((dirPath, v) {
      for (final e in (v['files'] as List)) {
        final r = e as List;
        final name = r[0] as String;
        out.add(DocFile(
          path: p.join(dirPath as String, name),
          name: name,
          size: r[1] as int,
          modified: DateTime.fromMillisecondsSinceEpoch(r[2] as int),
          kind: kindOf(name),
        ));
      }
    });
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }
}

/// Ayrı isolate'ta çalışır. Sadece düz Map/List/num/String kullanır.
Map<String, dynamic> _scan(Map<String, dynamic> old) {
  final oldDirs = (old['dirs'] as Map?) ?? {};
  final newDirs = <String, dynamic>{};
  final queue = <String>[DeviceIndex._root];

  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    final dir = Directory(path);

    int mtime;
    try {
      mtime = dir.statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      continue;
    }

    final cached = oldDirs[path];
    if (cached != null && cached['m'] == mtime) {
      // Klasör değişmemiş: içeriği yeniden okuma.
      newDirs[path] = cached;
      for (final s in (cached['sub'] as List)) {
        queue.add(p.join(path, s as String));
      }
      continue;
    }

    final subs = <String>[];
    final files = <List<dynamic>>[];
    try {
      for (final e in dir.listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (name.startsWith('.') ||
              DeviceIndex._skipDirs.contains(name.toLowerCase())) {
            continue;
          }
          subs.add(name);
        } else if (e is File) {
          final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
          if (DeviceIndex._exts.contains(ext)) {
            final st = e.statSync();
            files.add([name, st.size, st.modified.millisecondsSinceEpoch]);
          }
        }
      }
    } catch (_) {}

    newDirs[path] = {'m': mtime, 'sub': subs, 'files': files};
    for (final s in subs) {
      queue.add(p.join(path, s));
    }
  }
  return {'dirs': newDirs};
}
