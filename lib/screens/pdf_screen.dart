import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../ink/ink_core.dart';
import '../services/annotation_store.dart';
import '../services/file_service.dart';
import '../services/pdf_export.dart';
import '../services/recent_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page_notes_button.dart';
import '../widgets/quick_scroll_rail.dart';
import '../widgets/share_with_notes_button.dart';

enum _Menu { shareInk, shareOriginal, saveCopy, overwrite, clear, external }

class PdfScreen extends StatefulWidget {
  final String path;
  const PdfScreen({super.key, required this.path});

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  final _controller = PdfViewerController();
  InkModel? _model;
  bool _pen = false;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await AnnotationStore.load(widget.path);
    if (!mounted) return;
    setState(() => _model = InkModel(saved));
  }

  void _save() => AnnotationStore.save(widget.path, _model!.strokes);

  void _togglePen() {
    setState(() => _pen = !_pen);
    _model!.update(() => _model!.pen = _pen);
  }

  int? get _pageCount {
    try {
      return (_controller.pageCount as int?);
    } catch (_) {
      return null;
    }
  }

  void _go(int delta) {
    try {
      final cur = _controller.pageNumber ?? 1;
      final count = _pageCount ?? 9999;
      _controller.goToPage(pageNumber: (cur + delta).clamp(1, count));
    } catch (_) {}
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
      case _Menu.clear:
        _clear();
      case _Menu.external:
        OpenFilex.open(widget.path);
    }
  }

  // ───────────── arayüz ─────────────

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final pageCount = _pageCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(fileTitle(widget.path), overflow: TextOverflow.ellipsis),
        actions: [
          ShareWithNotesButton(documentPath: widget.path),
          PageNotesButton(
            documentPath: widget.path,
            pageKey: () => 'pdf-${_controller.pageNumber ?? 1}',
            pageLabel: () => 'Sayfa ${_controller.pageNumber ?? 1}',
          ),
          IconButton(
            tooltip: _pen ? 'Kaydırma moduna geç' : 'Kalemle yaz / çiz',
            isSelected: _pen,
            style: _pen
                ? IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: model == null ? null : _togglePen,
            icon: const Icon(Icons.draw_rounded),
          ),
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
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PdfViewer.file(
                          widget.path,
                          controller: _controller,
                          params: PdfViewerParams(
                            backgroundColor: Pal.of(context).canvas,
                            onPageChanged: (pageNumber) {
                              final page =
                                  pageNumber ?? _controller.pageNumber ?? 1;
                              if (_currentPage == page || !mounted) return;
                              setState(() => _currentPage = page);
                            },
                            // Kalem modunda tek parmakla kaydırma kapanır,
                            // iki parmakla yakınlaştırma açık kalır.
                            panEnabled: !_pen,
                            scaleEnabled: true,
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
                if (_pen)
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
    );
  }
}
