import 'dart:io';

import 'package:flutter/material.dart';

import '../ink/ink_session.dart';
import '../widgets/common.dart';

class ImageScreen extends StatefulWidget {
  final String path;
  const ImageScreen({super.key, required this.path});

  @override
  State<ImageScreen> createState() => _ImageScreenState();
}

class _ImageScreenState extends State<ImageScreen> {
  late final InkSession _ink = InkSession(widget.path);

  @override
  void dispose() {
    _ink.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    _ink.adaptColor(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(fileTitle(widget.path), overflow: TextOverflow.ellipsis),
        actions: [
          _ink.penButton(context, _refresh),
          ...fileActions(context, widget.path),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _ink.watch(
              () => InteractiveViewer(
                maxScale: 6,
                panEnabled: !_ink.pen,
                child: Center(
                  child: _ink.overlay(
                    page: 1,
                    child: Image.file(File(widget.path)),
                  ),
                ),
              ),
            ),
          ),
          if (_ink.pen) _ink.toolbar(context, _refresh),
        ],
      ),
    );
  }
}
