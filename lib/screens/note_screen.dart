import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/file_service.dart';
import '../services/recent_store.dart';
import '../widgets/common.dart';
import 'viewer_router.dart';

class NoteScreen extends StatefulWidget {
  /// null ise yeni not açılır.
  final String? path;
  const NoteScreen({super.key, this.path});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _path;
  bool _dirty = false;
  bool _loading = true;

  bool get _isNew => _path == null;

  @override
  void initState() {
    super.initState();
    _path = widget.path;
    _init();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_path != null) {
      try {
        _body.text = await File(_path!).readAsString();
      } catch (_) {}
      _title.text = p.basenameWithoutExtension(_path!);
    }
    _body.addListener(() {
      if (!_dirty && !_loading) setState(() => _dirty = true);
    });
    _title.addListener(() {
      if (!_dirty && !_loading) setState(() => _dirty = true);
    });
    if (mounted) setState(() => _loading = false);
  }

  String get _safeTitle {
    final t = _title.text.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return t.isEmpty ? 'Not' : t;
  }

  Future<void> _save() async {
    if (_isNew) {
      final dir = await FileService.docsDir();
      _path = await FileService.uniquePath(dir.path, '$_safeTitle.txt');
    }
    await File(_path!).writeAsString(_body.text);
    await RecentStore.add(_path!);
    if (!mounted) return;
    setState(() => _dirty = false);
    toast(context, 'Kaydedildi');
  }

  Future<void> _exportPdf() async {
    pw.Font? font;
    try {
      final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      font = pw.Font.ttf(data);
    } catch (_) {}

    final doc = pw.Document(
      theme: font != null ? pw.ThemeData.withFont(base: font, bold: font) : null,
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(44),
        build: (_) => [
          pw.Header(level: 0, text: _title.text.trim().isEmpty ? 'Not' : _title.text.trim()),
          pw.Paragraph(
            text: _body.text,
            style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
          ),
        ],
      ),
    );

    final dir = await FileService.docsDir();
    final out = await FileService.uniquePath(dir.path, '$_safeTitle.pdf');
    await File(out).writeAsBytes(await doc.save());
    if (!mounted) return;
    if (font == null) {
      toast(context, 'PDF hazır. Türkçe harfler için NotoSans fontunu ekle.');
    }
    await openDocument(context, out);
  }

  Future<void> _onBack() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Değişiklikleri kaydet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Kaydetme')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Kaydet')),
        ],
      ),
    );
    if (choice == null || choice == 'cancel') return;
    if (choice == 'save') await _save();
    if (!mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final words = _body.text.trim().isEmpty
        ? 0
        : _body.text.trim().split(RegExp(r'\s+')).length;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isNew
              ? TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    hintText: 'Başlık',
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                )
              : Text(fileTitle(_path!), overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Kaydet',
              onPressed: _dirty || _isNew ? _save : null,
              icon: const Icon(Icons.save_rounded),
            ),
            IconButton(
              tooltip: 'PDF yap',
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: TextField(
                        controller: _body,
                        maxLines: null,
                        expands: true,
                        autofocus: _isNew,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontSize: 17, height: 1.55),
                        decoration: const InputDecoration(
                          hintText: 'Yazmaya başla…',
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '$words kelime',
                        style: const TextStyle(color: Color(0xFF7A8594), fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
