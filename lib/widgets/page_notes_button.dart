import 'package:flutter/material.dart';

import '../screens/page_notes_screen.dart';

class PageNotesButton extends StatelessWidget {
  final String documentPath;
  final String Function() pageKey;
  final String Function() pageLabel;

  const PageNotesButton({
    super.key,
    required this.documentPath,
    required this.pageKey,
    required this.pageLabel,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Bu sayfanın notları',
        icon: const Icon(Icons.sticky_note_2_outlined),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PageNotesScreen(
                documentPath: documentPath,
                pageKey: pageKey(),
                pageLabel: pageLabel(),
              ),
            ),
          );
        },
      );
}
