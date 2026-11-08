import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ink/ink_session.dart';
import '../services/file_service.dart';
import '../services/recent_store.dart';
import '../widgets/common.dart';
import '../widgets/page_notes_button.dart';
import '../widgets/quick_scroll_rail.dart';
import '../widgets/share_with_notes_button.dart';
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
  final _bodyScrollController = ScrollController();
  String? _path;
  InkSession? _ink;
  bool _dirty = false;
  bool _loading = true;
  int _wordCount = 0;
  Timer? _wordCountTimer;

  bool get _isNew => _path == null;

  @override
  void initState() {
    super.initState();
    _path = widget.path;
    if (_path != null) _ink = InkSession(_path!);
    _init();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _wordCountTimer?.cancel();
    _bodyScrollController.dispose();
    _ink?.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _togglePen() {
    final ink = _ink;
    if (ink == null) {
      toast(context, 'Çizmek için önce notu kaydet');
      return;
    }
    ink.toggle();
    setState(() {});
  }

  Future<void> _init() async {
    if (_path != null) {
      try {
        _body.text = await File(_path!).readAsString();
      } catch (_) {}
      _title.text = p.basenameWithoutExtension(_path!);
    }
    _wordCount = _countWords(_body.text);
    _body.addListener(() {
      if (!_dirty && !_loading) setState(() => _dirty = true);
      _scheduleWordCountUpdate();
    });
    _title.addListener(() {
      if (!_dirty && !_loading) setState(() => _dirty = true);
    });
    if (mounted) setState(() => _loading = false);
  }

  int _countWords(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
  }

  void _scheduleWordCountUpdate() {
    _wordCountTimer?.cancel();
    _wordCountTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final count = _countWords(_body.text);
      if (count != _wordCount) setState(() => _wordCount = count);
    });
  }

  String get _safeTitle {
    final t = _title.text.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return t.isEmpty ? 'Not' : t;
  }

  Future<void> _save() async {
    if (_isNew) {
      final dir = await FileService.docsDir();
      _path = await FileService.uniquePath(dir.path, '$_safeTitle.txt');
      _ink ??= InkSession(_path!);
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
      theme: font != null
          ? pw.ThemeData.withFont(base: font, bold: font)
          : null,
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(44),
        build: (_) => [
          pw.Header(
            level: 0,
            text: _title.text.trim().isEmpty ? 'Not' : _title.text.trim(),
          ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Kaydetme'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Kaydet'),
          ),
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
    final ink = _ink;
    ink?.adaptColor(context);
    final penOn = ink?.pen == true;

    final textArea = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: TextField(
        controller: _body,
        scrollController: _bodyScrollController,
        maxLines: null,
        expands: true,
        autofocus: _isNew,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontSize: 17, height: 1.55),
        decoration: const InputDecoration(
          hintText: 'Yazmaya başla…',
          border: InputBorder.none,
        ),
      ),
    );

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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Text(fileTitle(_path!), overflow: TextOverflow.ellipsis),
          actions: [
            if (_path != null)
              PageNotesButton(
                documentPath: _path!,
                pageKey: () => 'note-1',
                pageLabel: () => 'Not',
              ),
            if (_path != null) ShareWithNotesButton(documentPath: _path!),
            IconButton(
              tooltip: penOn ? 'Yazma moduna geç' : 'Kalemle çiz',
              isSelected: penOn,
              style: penOn
                  ? IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    )
                  : null,
              onPressed: _togglePen,
              icon: const Icon(Icons.draw_rounded),
            ),
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
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ink == null
                              ? textArea
                              : ink.watch(
                                  () => ink.overlay(page: 1, child: textArea),
                                ),
                        ),
                        Positioned(
                          right: 6,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: QuickScrollRail(
                              controller: _bodyScrollController,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (ink != null && ink.pen) ink.toolbar(context, _refresh),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '$_wordCount kelime',
                        style: const TextStyle(
                          color: Color(0xFF7A8594),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
