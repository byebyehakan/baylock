import 'dart:io';

import 'package:flutter/material.dart';

import '../widgets/common.dart';

class ImageScreen extends StatelessWidget {
  final String path;
  const ImageScreen({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileTitle(path), overflow: TextOverflow.ellipsis),
        actions: fileActions(context, path),
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.file(File(path))),
      ),
    );
  }
}
