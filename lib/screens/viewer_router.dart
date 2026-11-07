import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../models/doc_item.dart';
import '../services/page_notes_bundle_service.dart';
import '../services/recent_store.dart';
import 'image_screen.dart';
import 'note_screen.dart';
import 'office_screens.dart';
import 'pdf_screen.dart';
import 'sheet_screen.dart';
import 'slides_screen.dart';

/// Dosya türüne göre doğru görüntüleyiciyi açar.
/// Uygulama içinde gösteremediği biçimlerde (.doc, .xls, .ppt ...) sistemdeki
/// başka bir uygulamaya devreder.
Future<void> openDocument(BuildContext context, String path) async {
  var documentPath = path;
  if (p.extension(path).toLowerCase() == '.baylock') {
    try {
      documentPath = await const PageNotesBundleService().importPackage(path);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Paket açılamadı: $error')));
      }
      return;
    }
  }
  await RecentStore.add(documentPath);
  if (!context.mounted) return;

  final ext = p.extension(documentPath).toLowerCase();
  Widget? page;
  switch (kindOf(documentPath)) {
    case DocKind.pdf:
      page = PdfScreen(path: documentPath);
    case DocKind.sheet:
      if (ext == '.xlsx' || ext == '.csv') page = SheetScreen(path: documentPath);
    case DocKind.word:
      if (ext == '.docx') page = WordScreen(path: documentPath);
    case DocKind.slides:
      if (ext == '.pptx') page = SlidesScreen(path: documentPath);
    case DocKind.text:
      page = NoteScreen(path: documentPath);
    case DocKind.image:
      page = ImageScreen(path: documentPath);
    case DocKind.other:
      break;
  }

  if (page == null) {
    await OpenFilex.open(documentPath);
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
}
