import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../ink/ink_core.dart';
import '../services/annotation_store.dart';
import '../services/document_navigation_store.dart';
import '../services/file_service.dart';
import '../services/pdf_export.dart';
import '../services/page_notes_store.dart';
import '../services/recent_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/document_tool_dock.dart';
import '../widgets/page_notes_button.dart';
import '../widgets/quick_scroll_rail.dart';
import '../widgets/share_with_notes_button.dart';

enum _Menu {
  shareInk,
  shareOriginal,
  saveCopy,
  overwrite,
  exportWithNotes,
  clear,
  external,
}

class PdfScreen extends StatefulWidget {
  final String path;
  const PdfScreen({super.key, required this.path});

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  final _controller = PdfViewerController();
  final _searchController = TextEditingController();
  final _navigationStore = const DocumentNavigationStore();
  final _notesStore = const PageNotesStore();
  InkModel? _model;
  PdfTextSearcher? _textSearcher;
  bool _manualZoom = false;
  bool _showSearch = false;
  bool _restoringPosition = true;
  int _currentPage = 1;
  Set<int> _bookmarks = {};
  Timer? _positionSaveTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBookmarks();
  }

  @override
  void dispose() {
    _positionSaveTimer?.cancel();
    unawaited(_savePositionOnDispose());
    _searchController.dispose();
    _textSearcher?.dispose();
    _model?.dispose();
    super.dispose();
  }

  Future<void> _savePositionOnDispose() async {
    if (_restoringPosition) return;
    try {
      await _navigationStore.saveLastPage(widget.path, _currentPage);
    } catch (error) {
      debugPrint('Okuma konumu kapatılırken kaydedilemedi: $error');
    }
  }

  Future<void> _load() async {
    final saved = await AnnotationStore.load(widget.path);
    if (!mounted) return;
    setState(() => _model = InkModel(saved));
  }

  void _save() => AnnotationStore.save(widget.path, _model!.strokes);

  void _onSearchUpdated() {
    if (mounted) setState(() {});
  }

  void _initializeTextSearcher() {
    if (_textSearcher != null || !_controller.isReady) return;
    final searcher = PdfTextSearcher(_controller)
      ..addListener(_onSearchUpdated);
    setState(() => _textSearcher = searcher);
  }

  void _paintSearchMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    _textSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  Future<void> _restorePosition() async {
    try {
      final page = await _navigationStore.lastPage(widget.path);
      if (page != null && page > 1 && page <= (_pageCount ?? 0)) {
        await _controller.goToPage(pageNumber: page, duration: Duration.zero);
      }
    } catch (error) {
      if (mounted) toast(context, 'Son sayfa açılamadı: $error');
    } finally {
      _restoringPosition = false;
    }
  }

  Future<void> _loadBookmarks() async {
    try {
      final pages = await _navigationStore.bookmarks(widget.path);
      final pageCount = _pageCount;
      if (mounted) {
        setState(
          () => _bookmarks = pages
              .where((page) => pageCount == null || page <= pageCount)
              .toSet(),
        );
      }
    } catch (error) {
      if (mounted) toast(context, 'Yer imleri yüklenemedi: $error');
    }
  }

  void _schedulePositionSave(int page) {
    if (_restoringPosition) return;
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        await _navigationStore.saveLastPage(widget.path, page);
      } catch (error) {
        if (mounted) toast(context, 'Okuma konumu kaydedilemedi: $error');
      }
    });
  }

  Future<void> _toggleCurrentBookmark() async {
    try {
      final isBookmarked = await _navigationStore.toggleBookmark(
        widget.path,
        _currentPage,
      );
      if (mounted) {
        setState(() {
          if (isBookmarked) {
            _bookmarks.add(_currentPage);
          } else {
            _bookmarks.remove(_currentPage);
          }
        });
      }
    } catch (error) {
      if (mounted) toast(context, 'Yer imi kaydedilemedi: $error');
    }
  }

  Future<void> _showBookmarks() async {
    final count = _pageCount;
    final pages =
        _bookmarks.where((page) => count == null || page <= count).toList()
          ..sort();
    if (pages.isEmpty) {
      toast(context, 'Henüz yer imi eklenmedi');
      return;
    }
    final page = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Yer imleri',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final page in pages)
              ListTile(
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: Text('Sayfa $page'),
                onTap: () => Navigator.pop(context, page),
              ),
          ],
        ),
      ),
    );
    if (page != null) {
      await _controller.goToPage(pageNumber: page);
    }
  }

  void _onSearchChanged(String query) {
    final searcher = _textSearcher;
    if (searcher == null) return;
    final normalized = query.trim();
    if (normalized.isEmpty) {
      searcher.resetTextSearch();
      return;
    }
    searcher.startTextSearch(normalized);
  }

  void _moveSearch(int delta) {
    final searcher = _textSearcher;
    if (searcher == null) return;
    final matches = searcher.matches;
    if (matches.isEmpty) return;
    final current = searcher.currentIndex ?? 0;
    final next = (current + delta + matches.length) % matches.length;
    searcher.goToMatchOfIndex(next);
  }

  Future<void> _exportWithNotes() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Notlarla PDF oluştur'),
          content: const Text(
            'Orijinal PDF değişmeden kalır. Yeni PDF’e çizimler işlenir ve '
            'sayfa notları sona eklenir. Çizimlerle birleştirilen kaynak '
            'sayfalar görüntü olacağından metin seçilemez olur.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('PDF oluştur'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final pageCount = _pageCount ?? 0;
      final notes = await _notesStore.loadAll(
        widget.path,
        legacyPageKeys: [
          for (var page = 1; page <= pageCount; page++) 'pdf-$page',
        ],
      );
      final output = await FileService.uniquePath(
        (await FileService.docsDir()).path,
        '${p.basenameWithoutExtension(widget.path)} (notlarla).pdf',
      );
      final saved = await _withProgress<String>((msg) async {
        await exportAnnotatedPdf(
          srcPath: widget.path,
          strokes: _model!.strokes,
          outPath: output,
          totalPages: pageCount,
          notesByPage: notes,
          onProgress: (done, total) {
            msg.value = total == null
                ? 'PDF sayfası $done işleniyor…'
                : 'PDF sayfası $done / $total işleniyor…';
          },
        );
        return output;
      });
      if (saved == null || !mounted) return;
      await RecentStore.add(saved);
      if (mounted) toast(context, 'Notlar PDF olarak kaydedildi');
    } catch (error) {
      if (mounted) toast(context, 'Notlarla PDF oluşturulamadı: $error');
    }
  }

  int? get _pageCount {
    try {
      return (_controller.pageCount as int?);
    } catch (_) {
      return null;
    }
  }

  String get _searchMatchCountLabel {
    final searcher = _textSearcher;
    if (searcher == null) return '0/0';
    final currentIndex = searcher.currentIndex;
    return '${currentIndex == null ? 0 : currentIndex + 1}/${searcher.matches.length}';
  }

  void _go(int delta) {
    try {
      final cur = _controller.pageNumber ?? 1;
      final count = _pageCount ?? 9999;
      _controller.goToPage(pageNumber: (cur + delta).clamp(1, count));
    } catch (_) {}
  }

  Future<void> _fitCurrentPageWidth() async {
    _manualZoom = false;
    final matrix = _controller.calcMatrixFitWidthForPage(
      pageNumber: _currentPage,
    );
    if (matrix != null) {
      await _controller.goTo(
        matrix,
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  // ───────────── dışa aktarma ─────────────

  Future<bool?> _askScope() {
    final m = _model!;
    final inked = m.inkPages.length;
    final total = _pageCount;
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_rounded),
              title: Text(
                total == null ? 'Tüm sayfalar' : 'Tüm sayfalar ($total)',
              ),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.draw_rounded),
              title: Text('Sadece çizim yapılan sayfalar ($inked)'),
              subtitle: const Text(
                'Ders notu çıkarmak için ideal, dosya küçük olur',
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<T?> _withProgress<T>(
    Future<T> Function(ValueNotifier<String> msg) job,
  ) async {
    final msg = ValueNotifier<String>('Hazırlanıyor…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: msg,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                Text(v),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await job(msg);
    } catch (e) {
      if (mounted) toast(context, 'Hata: $e');
      return null;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _export(String out, bool onlyInked, ValueNotifier<String> msg) {
    return exportAnnotatedPdf(
      srcPath: widget.path,
      strokes: _model!.strokes,
      outPath: out,
      onlyInked: onlyInked,
      totalPages: _pageCount,
      onProgress: (d, t) =>
          msg.value = t == null ? 'Sayfa $d işleniyor…' : 'Sayfa $d / $t',
    );
  }

  String get _baseName => p.basenameWithoutExtension(widget.path);

  Future<void> _shareInk() async {
    final m = _model!;
    if (!m.hasInk) {
      toast(context, 'Henüz çizim yok, orijinal PDF paylaşılıyor');
      await Share.shareXFiles([XFile(widget.path)]);
      return;
    }
    final onlyInked = await _askScope();
    if (onlyInked == null || !mounted) return;
    final tmp = await getTemporaryDirectory();
    final out = p.join(tmp.path, '$_baseName (çizimli).pdf');
    final ok = await _withProgress<bool>((msg) async {
      await _export(out, onlyInked, msg);
      return true;
    });
    if (ok == true) await Share.shareXFiles([XFile(out)]);
  }

  Future<void> _saveCopy() async {
    final m = _model!;
    if (!m.hasInk) {
      toast(context, 'Kaydedilecek çizim yok');
      return;
    }
    final onlyInked = await _askScope();
    if (onlyInked == null || !mounted) return;

    var dir = p.dirname(widget.path);
    var out = await FileService.uniquePath(dir, '$_baseName (çizimli).pdf');
    final saved = await _withProgress<String>((msg) async {
      try {
        await _export(out, onlyInked, msg);
      } on FileSystemException {
        // Klasöre yazılamadıysa uygulamanın kendi klasörüne kaydet.
        dir = (await FileService.docsDir()).path;
        out = await FileService.uniquePath(dir, '$_baseName (çizimli).pdf');
        await _export(out, onlyInked, msg);
      }
      return out;
    });
    if (saved == null || !mounted) return;
    await RecentStore.add(saved);
    if (mounted) toast(context, 'Kaydedildi: ${p.basename(saved)}');
  }

  Future<void> _overwrite() async {
    final m = _model!;
    if (!m.hasInk) {
      toast(context, 'Kaydedilecek çizim yok');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Orijinalin üzerine yaz?'),
        content: const Text(
          'Çizimler PDF\'e kalıcı olarak işlenir ve geri alınamaz. '
          'Sayfalar görüntüye dönüşeceği için metinler seçilemez olur.\n\n'
          'Emin değilsen "Çizimli kopya kaydet"i kullan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Üzerine yaz'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final tmp = await getTemporaryDirectory();
    final out = p.join(tmp.path, '$_baseName (geçici).pdf');
    final done = await _withProgress<bool>((msg) async {
      await _export(out, false, msg); // üzerine yazarken tüm sayfalar korunur
      await File(out).copy(widget.path);
      return true;
    });
    if (done != true || !mounted) return;

    // Çizimler artık PDF'in içinde, ayrı kaydı temizle.
    _model!.clearAll();
    await AnnotationStore.save(widget.path, {});
    if (!mounted) return;
    toast(context, 'Orijinal PDF güncellendi');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PdfScreen(path: widget.path)),
    );
  }

  Future<void> _clear() async {
    final m = _model!;
    if (!m.hasInk) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm çizimler silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      m.clearAll();
      _save();
    }
  }

  void _onMenu(_Menu v) {
    switch (v) {
      case _Menu.shareInk:
        _shareInk();
      case _Menu.shareOriginal:
        Share.shareXFiles([XFile(widget.path)]);
      case _Menu.saveCopy:
        _saveCopy();
      case _Menu.overwrite:
        _overwrite();
      case _Menu.exportWithNotes:
        _exportWithNotes();
      case _Menu.clear:
        _clear();
      case _Menu.external:
        OpenFilex.open(widget.path);
    }
  }

  Widget _buildPdfToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final isBookmarked = _bookmarks.contains(_currentPage);

    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool selected = false,
    }) {
      final style = ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      final button = selected
          ? FilledButton.tonalIcon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: Text(label),
            );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: button,
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              action(
                icon: Icons.search_rounded,
                label: 'Ara',
                selected: _showSearch,
                onPressed: _textSearcher == null
                    ? null
                    : () => setState(() => _showSearch = !_showSearch),
              ),
              action(
                icon: isBookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_add_outlined,
                label: isBookmarked ? 'Yer imi' : 'Yer imi ekle',
                selected: isBookmarked,
                onPressed: _toggleCurrentBookmark,
              ),
              action(
                icon: Icons.bookmarks_outlined,
                label: 'Yer imleri',
                onPressed: _showBookmarks,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: PageNotesButton(
                  documentPath: widget.path,
                  pageKey: () => 'pdf-${_controller.pageNumber ?? 1}',
                  pageLabel: () => 'Sayfa ${_controller.pageNumber ?? 1}',
                  showLabel: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ShareWithNotesButton(
                  documentPath: widget.path,
                  showLabel: true,
                ),
              ),
              action(
                icon: Icons.fit_screen_rounded,
                label: 'Sayfayı sığdır',
                onPressed: _fitCurrentPageWidth,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────── arayüz ─────────────

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final pageCount = _pageCount;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(fileTitle(widget.path), overflow: TextOverflow.ellipsis),
            Text(
              'PDF · Sayfa $_currentPage${pageCount == null ? '' : ' / $pageCount'}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_Menu>(
            tooltip: 'Kaydet ve paylaş',
            enabled: model != null,
            onSelected: _onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _Menu.shareInk,
                child: ListTile(
                  leading: Icon(Icons.ios_share_rounded),
                  title: Text('Çizimli PDF\'i paylaş'),
                ),
              ),
              PopupMenuItem(
                value: _Menu.shareOriginal,
                child: ListTile(
                  leading: Icon(Icons.file_present_rounded),
                  title: Text('Orijinali paylaş'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _Menu.saveCopy,
                child: ListTile(
                  leading: Icon(Icons.save_alt_rounded),
                  title: Text('Çizimli kopya kaydet'),
                ),
              ),
              PopupMenuItem(
                value: _Menu.overwrite,
                child: ListTile(
                  leading: Icon(Icons.save_rounded),
                  title: Text('Orijinalin üzerine yaz'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _Menu.exportWithNotes,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Notlarla PDF oluştur'),
                ),
              ),
              PopupMenuItem(
                value: _Menu.clear,
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Çizimleri sil'),
                ),
              ),
              PopupMenuItem(
                value: _Menu.external,
                child: ListTile(
                  leading: Icon(Icons.open_in_new_rounded),
                  title: Text('Başka uygulamada aç'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: model == null
          ? const Center(child: CircularProgressIndicator())
          : DocumentToolDock(
              model: model,
              child: ListenableBuilder(
                listenable: model,
                builder: (_, __) => Column(
              children: [
                _buildPdfToolbar(context),
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'PDF içinde ara…',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Önceki eşleşme',
                          onPressed: () => _moveSearch(-1),
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                        IconButton(
                          tooltip: 'Sonraki eşleşme',
                          onPressed: () => _moveSearch(1),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                        Text(_searchMatchCountLabel),
                        IconButton(
                          tooltip: 'Aramayı kapat',
                          onPressed: () {
                            _searchController.clear();
                            _textSearcher?.resetTextSearch();
                            setState(() => _showSearch = false);
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PdfViewer.file(
                          widget.path,
                          controller: _controller,
                          params: PdfViewerParams(
                            backgroundColor: Pal.of(context).canvas,
                            onViewerReady: (_, __) {
                              _initializeTextSearcher();
                              _restorePosition();
                            },
                            onPageChanged: (pageNumber) {
                              final page =
                                  pageNumber ?? _controller.pageNumber ?? 1;
                              if (_currentPage == page || !mounted) return;
                              setState(() => _currentPage = page);
                              _schedulePositionSave(page);
                              if (!_manualZoom) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted && !_manualZoom) {
                                    _fitCurrentPageWidth();
                                  }
                                });
                              }
                            },
                            onInteractionUpdate: (details) {
                              if ((details.scale - 1).abs() > 0.01) {
                                _manualZoom = true;
                              }
                            },
                            // Kalem modunda tek parmakla kaydırma kapanır,
                            // iki parmakla yakınlaştırma açık kalır.
                            panEnabled: !model.pen,
                            scaleEnabled: true,
                            pagePaintCallbacks: [_paintSearchMatches],
                            pageOverlaysBuilder: (context, pageRect, page) => [
                              InkLayer(
                                key: ValueKey('ink-${page.pageNumber}'),
                                model: model,
                                page: page.pageNumber,
                                size: pageRect.size,
                                onChanged: _save,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if ((pageCount ?? 0) > 10)
                        Positioned(
                          right: 6,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: QuickScrollRail(
                              pageCount: pageCount,
                              currentPage: _currentPage,
                              onPageSelected: (page) {
                                _controller.goToPage(pageNumber: page);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (model.pen)
                  InkToolbar(
                    model: model,
                    onChanged: _save,
                    extra: [
                      IconButton(
                        tooltip: 'Önceki sayfa',
                        onPressed: () => _go(-1),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      IconButton(
                        tooltip: 'Sonraki sayfa',
                        onPressed: () => _go(1),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ],
                  ),
                  ],
                ),
              ),
            ),
    );
  }
}
