import 'dart:io';

import 'package:baylock/ink/ink_core.dart';
import 'package:baylock/models/page_note.dart';
import 'package:baylock/services/page_notes_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'saves note sheets and drawings separately for each source page',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'page-notes-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = PageNotesStore(baseDirectory: directory);
      final note = PageNote(
        id: 'note-1',
        text: 'Sınavda önemli',
        fontFamily: 'serif',
        fontSize: 22,
        paperStyle: NotePaperStyle.grid,
        strokes: [
          InkStroke(
            tool: InkTool.ballpoint,
            color: const Color(0xFF14202F).toARGB32(),
            width: 0.01,
            pts: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
          ),
        ],
      );

      await store.save('sunum.pptx', 'slide-3', [note]);
      await store.save('sunum.pptx', 'slide-4', []);

      final loaded = await store.load('sunum.pptx', 'slide-3');
      expect(loaded, hasLength(1));
      expect(loaded.single.text, 'Sınavda önemli');
      expect(loaded.single.fontFamily, 'serif');
      expect(loaded.single.fontSize, 22);
      expect(loaded.single.paperStyle, NotePaperStyle.grid);
      expect(loaded.single.strokes, hasLength(1));
      expect(await store.load('sunum.pptx', 'slide-4'), isEmpty);
      expect(await store.load('baska.pptx', 'slide-3'), isEmpty);
    },
  );

  test('existing note data defaults to blank paper', () {
    final note = PageNote.fromJson({
      'id': 'old-note',
      'text': 'Eski not',
      'fontFamily': 'sans-serif',
      'fontSize': 18,
      'strokes': [],
    });

    expect(note.paperStyle, NotePaperStyle.blank);
    expect(PageNote.fromJson(note.toJson()).paperStyle, NotePaperStyle.blank);
  });
}
