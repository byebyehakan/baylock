import 'package:flutter/material.dart';

import '../screens/page_notes_screen.dart';

class PageNotesButton extends StatelessWidget {
  final String documentPath;
  final String Function() pageKey;
  final String Function() pageLabel;
  final bool showLabel;

  const PageNotesButton({
    super.key,
    required this.documentPath,
    required this.pageKey,
    required this.pageLabel,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    void openNotes() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PageNotesScreen(
            documentPath: documentPath,
            pageKey: pageKey(),
            pageLabel: pageLabel(),
          ),
        ),
      );
    }

    if (showLabel) {
      return OutlinedButton.icon(
        onPressed: openNotes,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
        label: const Text('Sayfa notları'),
      );
    }

    return IconButton(
      tooltip: 'Bu sayfanın notları',
      icon: const Icon(Icons.sticky_note_2_outlined),
      onPressed: openNotes,
    );
  }
}
