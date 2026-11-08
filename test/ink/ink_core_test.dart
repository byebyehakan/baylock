import 'package:flutter/material.dart';
import 'package:baylock/ink/ink_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finger drawing is enabled by default', () {
    final model = InkModel();
    addTearDown(model.dispose);

    expect(model.finger, isTrue);
  });

  test('page revisions track drawing changes but ignore tool changes', () {
    final model = InkModel();
    addTearDown(model.dispose);

    expect(model.revisionForPage(1), 0);
    model.update(() => model.color = Colors.red);
    expect(model.revisionForPage(1), 0);

    model.add(
      1,
      InkStroke(
        tool: InkTool.ballpoint,
        color: Colors.black.toARGB32(),
        width: 0.01,
        pts: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
      ),
    );
    expect(model.revisionForPage(1), 1);

    model.undo();
    expect(model.revisionForPage(1), 2);

    model.redo();
    expect(model.revisionForPage(1), 3);

    model.clearAll();
    expect(model.revisionForPage(1), 4);
  });
}
