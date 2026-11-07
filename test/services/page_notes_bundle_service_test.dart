import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:baylock/ink/ink_core.dart';
import 'package:baylock/models/page_note.dart';
import 'package:baylock/services/page_notes_bundle_service.dart';
import 'package:baylock/services/page_notes_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips the original document and notes in a Baylock package', () async {
    final root = await Directory.systemTemp.createTemp('baylock-bundle-test-');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}\\lecture.pptx');
    final sourceBytes = [1, 2, 3, 4, 5];
    await source.writeAsBytes(sourceBytes);

    final notesStore = PageNotesStore(
      baseDirectory: Directory('${root.path}\\note-store'),
    );
    await notesStore.save(source.path, 'slide-3', [
      PageNote(
        id: 'note-a',
        text: 'Önemli slayt',
        fontFamily: 'serif',
        fontSize: 22,
        strokes: [
          InkStroke(
            tool: InkTool.ballpoint,
            color: const Color(0xFF14202F).toARGB32(),
            width: 0.01,
            pts: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
          ),
        ],
      ),
    ]);
    var documentHash = 2166136261;
    for (final codeUnit in source.path.codeUnits) {
      documentHash = ((documentHash ^ codeUnit) * 16777619) & 0xFFFFFFFF;
    }
    await File(
      '${root.path}\\note-store\\page_notes\\lecture_${documentHash.toRadixString(16)}_index.json',
    ).delete();

    final service = PageNotesBundleService(
      notesStore: notesStore,
      importDirectory: Directory('${root.path}\\imported'),
    );
    final packageBytes = await service.createPackage(source.path);
    final packagePath = '${root.path}\\lecture.baylock';
    await File(packagePath).writeAsBytes(packageBytes);
    final importedPath = await service.importPackage(packagePath);

    expect(await File(importedPath).readAsBytes(), sourceBytes);
    final importedNotes = await notesStore.load(importedPath, 'slide-3');
    expect(importedNotes, hasLength(1));
    expect(importedNotes.single.text, 'Önemli slayt');
    expect(importedNotes.single.fontFamily, 'serif');
    expect(importedNotes.single.fontSize, 22);
    expect(importedNotes.single.strokes, hasLength(1));

    final archive = ZipDecoder().decodeBytes(packageBytes);
    final manifest = jsonDecode(
      utf8.decode(archive.findFile('baylock.json')!.content as List<int>),
    ) as Map<String, dynamic>;
    expect(manifest['format'], 'baylock-document');
    expect(archive.findFile('document/lecture.pptx'), isNotNull);
  });
}
