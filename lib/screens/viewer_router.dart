import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../models/doc_item.dart';
import '../services/recent_store.dart';
import 'image_screen.dart';
import 'note_screen.dart';
import 'office_screens.dart';
import 'pdf_screen.dart';
import 'sheet_screen.dart';

/// Dosya türüne göre doğru görüntüleyiciyi açar.
/// Uygulama içinde gösteremediği biçimlerde (.doc, .xls, .ppt ...) sistemdeki
/// başka bir uygulamaya devreder.
Future<void> openDocument(BuildContext context, String path) async {
  await RecentStore.add(path);
  if (!context.mounted) return;

  final ext = p.extension(path).toLowerCase();
  Widget? page;
  switch (kindOf(path)) {
    case DocKind.pdf:
      page = PdfScreen(path: path);
    case DocKind.sheet:
      if (ext == '.xlsx' || ext == '.csv') page = SheetScreen(path: path);
    case DocKind.word:
      if (ext == '.docx') page = WordScreen(path: path);
    case DocKind.slides:
      if (ext == '.pptx') page = SlidesScreen(path: path);
    case DocKind.text:
      page = NoteScreen(path: path);
    case DocKind.image:
      page = ImageScreen(path: path);
    case DocKind.other:
      break;
  }

  if (page == null) {
    await OpenFilex.open(path);
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
}
