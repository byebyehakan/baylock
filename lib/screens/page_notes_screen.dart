import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../ink/ink_core.dart';
import '../models/page_note.dart';
import '../services/file_service.dart';
import '../services/page_notes_pdf_export.dart';
import '../services/page_notes_store.dart';
import '../services/recent_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'viewer_router.dart';

class PageNotesScreen extends StatefulWidget {
  final String documentPath;
  final String pageKey;
  final String pageLabel;

  const PageNotesScreen({
    super.key,
    required this.documentPath,
    required this.pageKey,
    required this.pageLabel,
  });

  @override
  State<PageNotesScreen> createState() => _PageNotesScreenState();
}

class _PageNotesScreenState extends State<PageNotesScreen> {
  static const _fonts = <String, String>{
    'sans-serif': 'Sans',
    'serif': 'Serif',
    'monospace': 'Mono',
    'cursive': 'Cursive',
  };
  static const _fontSizes = [12.0, 14.0, 16.0, 18.0, 22.0, 28.0, 36.0];
  static const _paperStyles = <NotePaperStyle, (String, IconData)>{
    NotePaperStyle.blank: ('Boş', Icons.crop_square_rounded),
    NotePaperStyle.grid: ('Kareli', Icons.grid_on_rounded),
    NotePaperStyle.lined: ('Çizgili', Icons.reorder_rounded),
    NotePaperStyle.dotted: ('Noktalı', Icons.more_horiz_rounded),
  };
  static var _nextId = 0;

  final _store = const PageNotesStore();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  List<PageNote> _notes = [];
  int _index = 0;
  InkModel? _ink;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _pen = false;
  String? _error;
  Timer? _saveTimer;

  PageNote? get _current =>
      _notes.isEmpty || _index >= _notes.length ? null : _notes[_index];

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) unawaited(_persist());
    _textController
      ..removeListener(_onTextChanged)
      ..dispose();
    _scrollController.dispose();
    _ink?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await _store.load(widget.documentPath, widget.pageKey);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
      if (notes.isNotEmpty) _select(0);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Notlar yüklenemedi: $error';
        _loading = false;
      });
    }
  }

  void _onTextChanged() {
    final current = _current;
    if (current == null) return;
    _notes[_index] = current.copyWith(text: _textController.text);
    _markDirty();
  }

  void _markDirty({bool immediately = false}) {
    _dirty = true;
    _saveTimer?.cancel();
    if (immediately) {
      unawaited(_persist());
    } else {
      _saveTimer = Timer(const Duration(milliseconds: 350), _persist);
    }
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    _saveTimer?.cancel();
    if (!_dirty || _saving) return;
    _saving = true;
    try {
      do {
        _dirty = false;
        await _store.save(
          widget.documentPath,
          widget.pageKey,
          List<PageNote>.unmodifiable(_notes),
        );
      } while (_dirty);
      if (mounted) {
        setState(() => _error = null);
      }
    } catch (error) {
      _dirty = true;
      if (mounted) {
        setState(() => _error = 'Not kaydedilemedi: $error');
      }
    } finally {
      _saving = false;
    }
  }

  void _select(int index) {
    if (index < 0 || index >= _notes.length) return;
    if (_dirty) unawaited(_persist());
    _saveTimer?.cancel();
    final previousInk = _ink;
    _ink = null;
    previousInk?.dispose();
    _index = index;
    _textController
      ..removeListener(_onTextChanged)
      ..text = _notes[index].text
      ..addListener(_onTextChanged);
    _ink = InkModel({1: List<InkStroke>.from(_notes[index].strokes)});
    _ink!.pen = _pen;
    if (mounted) setState(() {});
  }

  void _addPage() {
    final note = PageNote(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
      text: '',
      fontFamily: 'sans-serif',
      fontSize: 18,
    );
    setState(() {
      _notes.add(note);
      _index = _notes.length - 1;
    });
    _select(_index);
    _markDirty(immediately: true);
  }

  void _updateCurrent(PageNote Function(PageNote current) update) {
    final current = _current;
    if (current == null) return;
    _notes[_index] = update(current);
    _markDirty(immediately: true);
  }

  void _togglePen() {
    _pen = !_pen;
    _ink?.update(() => _ink!.pen = _pen);
    setState(() {});
  }

  Future<void> _chooseFontFamily() async {
    final current = _current;
    if (current == null) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final font in _fonts.entries)
              ListTile(
                title: Text(font.value, style: TextStyle(fontFamily: font.key)),
                trailing: current.fontFamily == font.key
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, font.key),
              ),
          ],
        ),
      ),
    );
    if (result != null) {
      _updateCurrent((note) => note.copyWith(fontFamily: result));
    }
  }

  Future<void> _chooseFontSize() async {
    final current = _current;
    if (current == null) return;
    final result = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final size in _fontSizes)
              ListTile(
                title: Text(
                  '${size.toInt()} punto',
                  style: TextStyle(fontSize: size),
                ),
                trailing: current.fontSize == size
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, size),
              ),
          ],
        ),
      ),
    );
    if (result != null) {
      _updateCurrent((note) => note.copyWith(fontSize: result));
    }
  }

  Future<void> _choosePaperStyle() async {
    final current = _current;
    if (current == null) return;
    final result = await showModalBottomSheet<NotePaperStyle>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in _paperStyles.entries)
              ListTile(
                leading: Icon(entry.value.$2),
                title: Text(entry.value.$1),
                trailing: current.paperStyle == entry.key
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (result != null) {
      _updateCurrent((note) => note.copyWith(paperStyle: result));
    }
  }

  Future<void> _searchNotes() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notlarda ara'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Aranacak kelime'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Ara'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null || query.isEmpty) return;
    final matches = [
      for (var index = 0; index < _notes.length; index++)
        if (_notes[index].text.toLowerCase().contains(query.toLowerCase()))
          index,
    ];
    if (matches.isEmpty) {
      if (mounted) toast(context, 'Bu sayfanın notlarında eşleşme bulunamadı');
      return;
    }
    final selected = matches.length == 1
        ? matches.single
        : await showModalBottomSheet<int>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final index in matches)
                    ListTile(
                      title: Text('Not ${index + 1}'),
                      subtitle: Text(
                        _notes[index].text.replaceAll('\n', ' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, index),
                    ),
                ],
              ),
            ),
          );
    if (selected != null) _select(selected);
  }

  Future<void> _deletePage() async {
    final current = _current;
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not sayfası silinsin mi?'),
        content: const Text('Bu not sayfasındaki yazı ve çizimler silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _notes.removeAt(_index);
    if (_notes.isEmpty) {
      _ink?.dispose();
      _ink = null;
      _textController.clear();
      setState(() {});
    } else {
      _select(_index.clamp(0, _notes.length - 1));
    }
    _markDirty(immediately: true);
  }

  Future<void> _clearDrawing() async {
    final ink = _ink;
    if (ink == null || !ink.hasInk) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bu not sayfasındaki çizimler silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ink.clearAll();
    _updateCurrent((note) => note.copyWith(strokes: []));
  }

  Future<void> _close() async {
    _saveTimer?.cancel();
    await _persist();
    if (mounted && !_dirty) Navigator.pop(context);
  }

  Future<void> _exportNotesPdf() async {
    _saveTimer?.cancel();
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _persist();
    if (_dirty) {
      if (mounted) toast(context, 'Önce notların kaydedilmesi gerekiyor');
      return;
    }
    try {
      final notesByPage = await _store.loadAll(widget.documentPath);
      if (notesByPage.values.every((notes) => notes.isEmpty)) {
        if (mounted) toast(context, 'Dışa aktarılacak not bulunamadı');
        return;
      }
      final directory = await FileService.docsDir();
      final output = await FileService.uniquePath(
        directory.path,
        '${p.basenameWithoutExtension(widget.documentPath)} (notlar).pdf',
      );
      final bytes = await createPageNotesPdf(notesByPage);
      await File(output).writeAsBytes(bytes, flush: true);
      await RecentStore.add(output);
      if (!mounted) return;
      toast(context, 'Notlar PDF olarak kaydedildi');
      await openDocument(context, output);
    } catch (error) {
      if (mounted) toast(context, 'Notlar PDF yapılamadı: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final ink = _ink;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kapat',
          onPressed: _close,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('${widget.pageLabel} · Notlar'),
        actions: [
          IconButton(
            tooltip: 'Notlarda ara',
            onPressed: _loading || _notes.isEmpty ? null : _searchNotes,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Tüm notları PDF yap',
            onPressed: _loading ? null : _exportNotesPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          if (current != null) ...[
            IconButton(
              tooltip: 'Yazı tipi',
              onPressed: _chooseFontFamily,
              icon: const Icon(Icons.font_download_outlined),
            ),
            IconButton(
              tooltip: 'Yazı boyutu',
              onPressed: _chooseFontSize,
              icon: const Icon(Icons.format_size_rounded),
            ),
            IconButton(
              tooltip: 'Not kağıdı biçimi',
              onPressed: _choosePaperStyle,
              icon: Icon(_paperStyles[current.paperStyle]!.$2),
            ),
            IconButton(
              tooltip: _pen ? 'Yazı moduna geç' : 'Çizim moduna geç',
              isSelected: _pen,
              onPressed: _togglePen,
              icon: Icon(_pen ? Icons.keyboard_rounded : Icons.draw_rounded),
            ),
            IconButton(
              tooltip: 'Not sayfası ekle',
              onPressed: _addPage,
              icon: const Icon(Icons.note_add_outlined),
            ),
            IconButton(
              tooltip: 'Not sayfasını sil',
              onPressed: _deletePage,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ] else
            IconButton(
              tooltip: 'Not sayfası ekle',
              onPressed: _loading || _error != null ? null : _addPage,
              icon: const Icon(Icons.note_add_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _notes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                if (_notes.isNotEmpty) _pageSelector(),
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!),
                    actions: [
                      TextButton(
                        onPressed: _persist,
                        child: const Text('Yeniden dene'),
                      ),
                    ],
                  ),
                Expanded(
                  child: current == null || ink == null
                      ? _emptyNotes()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Pal.of(context).card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Pal.of(context).border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _noteCanvas(current, ink),
                          ),
                        ),
                ),
                if (current != null && ink != null && _pen)
                  InkToolbar(
                    model: ink,
                    onChanged: () => _updateCurrent(
                      (note) => note.copyWith(
                        strokes: List<InkStroke>.from(ink.of(1)),
                      ),
                    ),
                    extra: [
                      IconButton(
                        tooltip: 'Çizimleri temizle',
                        onPressed: ink.hasInk ? _clearDrawing : null,
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }

  Widget _pageSelector() => SizedBox(
    height: 54,
    child: ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _notes.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text('Not ${index + 1}'),
          selected: index == _index,
          onSelected: (_) => _select(index),
        ),
      ),
    ),
  );

  Widget _noteCanvas(PageNote note, InkModel ink) {
    final textField = Padding(
      padding: const EdgeInsets.all(20),
      child: TextField(
        controller: _textController,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        readOnly: _pen,
        style: TextStyle(
          fontFamily: note.fontFamily,
          fontSize: note.fontSize,
          height: 1.5,
          color: Pal.of(context).text,
        ),
        decoration: const InputDecoration(
          hintText: 'Bu sayfa için not yaz…',
          border: InputBorder.none,
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _NotePaperPainter(
              style: note.paperStyle,
              color: Pal.of(context).border,
            ),
          ),
        ),
        Positioned.fill(child: textField),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => InkLayer(
              key: ValueKey('note-ink-${note.id}'),
              model: ink,
              page: 1,
              size: constraints.biggest,
              onChanged: () => _updateCurrent(
                (current) =>
                    current.copyWith(strokes: List<InkStroke>.from(ink.of(1))),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyNotes() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            size: 52,
            color: Pal.of(context).muted,
          ),
          const SizedBox(height: 12),
          const Text(
            'Bu sayfada henüz not yok',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Yeni bir not sayfası oluşturup yazmaya veya çizmeye başlayabilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Pal.of(context).muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _addPage,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Not sayfası oluştur'),
          ),
        ],
      ),
    ),
  );
}

class _NotePaperPainter extends CustomPainter {
  final NotePaperStyle style;
  final Color color;

  const _NotePaperPainter({required this.style, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (style == NotePaperStyle.blank) return;
    const spacing = 24.0;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 0.7;
    if (style == NotePaperStyle.grid) {
      for (var x = spacing; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
    if (style == NotePaperStyle.grid || style == NotePaperStyle.lined) {
      for (var y = spacing; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
    if (style == NotePaperStyle.dotted) {
      for (var y = spacing; y < size.height; y += spacing) {
        for (var x = spacing; x < size.width; x += spacing) {
          canvas.drawCircle(Offset(x, y), 1.1, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_NotePaperPainter oldDelegate) =>
      style != oldDelegate.style || color != oldDelegate.color;
}
