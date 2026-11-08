import 'package:baylock/ink/ink_core.dart';
import 'package:baylock/models/page_note.dart';
import 'package:baylock/services/page_notes_pdf_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports page notes and drawings as a readable PDF file', () async {
    var fontLoaded = false;
    final bytes = await createPageNotesPdf({
      'pdf-2': [
        PageNote(
          id: 'note-2',
          text: 'Not ikinci sayfaya ait',
          fontFamily: 'sans-serif',
          fontSize: 18,
          paperStyle: NotePaperStyle.grid,
          strokes: [
            InkStroke(
              tool: InkTool.ballpoint,
              color: const Color(0xFF14202F).toARGB32(),
              width: 0.01,
              pts: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
            ),
          ],
        ),
      ],
      'pdf-10': [
        const PageNote(
          id: 'note-10',
          text: 'Not onuncu sayfaya ait',
          fontFamily: 'sans-serif',
          fontSize: 18,
        ),
      ],
    }, fontLoader: () async {
      fontLoaded = true;
      return pw.Font.helvetica();
    });

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    expect(fontLoaded, isTrue);
  });
}
