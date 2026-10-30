import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

List<Widget> fileActions(BuildContext context, String path) => [
      IconButton(
        tooltip: 'Paylaş',
        icon: const Icon(Icons.ios_share_rounded),
        onPressed: () => Share.shareXFiles([XFile(path)]),
      ),
      IconButton(
        tooltip: 'Başka uygulamada aç',
        icon: const Icon(Icons.open_in_new_rounded),
        onPressed: () => OpenFilex.open(path),
      ),
    ];

String fileTitle(String path) => p.basename(path);

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatDate(DateTime d) {
  const months = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
