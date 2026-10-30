import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../widgets/common.dart';

class PdfScreen extends StatelessWidget {
  final String path;
  const PdfScreen({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileTitle(path), overflow: TextOverflow.ellipsis),
        actions: fileActions(context, path),
      ),
      body: PdfViewer.file(path),
    );
  }
}
