import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/page_notes_bundle_service.dart';

class ShareWithNotesButton extends StatelessWidget {
  final String documentPath;

  const ShareWithNotesButton({super.key, required this.documentPath});

  Future<void> _share(BuildContext context) async {
    try {
      final bytes = await const PageNotesBundleService().createPackage(
        documentPath,
      );
      final temp = await getTemporaryDirectory();
      final name =
          '${p.basenameWithoutExtension(documentPath)}_${DateTime.now().microsecondsSinceEpoch}.baylock';
      final package = File(p.join(temp.path, name));
      await package.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(package.path),
      ], text: 'Baylock belgesi ve sayfa notları');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Notlarla paylaşılamadı: $error')),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Belgeyi notlarla paylaş',
    icon: const Icon(Icons.outbox_rounded),
    onPressed: () => _share(context),
  );
}
