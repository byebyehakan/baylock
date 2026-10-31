import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../ink/ink_core.dart';
import '../services/file_service.dart';
import '../services/recent_store.dart';
import '../widgets/common.dart';

enum Paper { blank, ruled, grid, dots }

const _paperNames = {
  Paper.blank: 'Boş',
  Paper.ruled: 'Çizgili',
  Paper.grid: 'Kareli',
  Paper.dots: 'Noktalı',
};

void paintPaper(Canvas canvas, Size size, Paper paper) {
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  final line = Paint()
    ..color = const Color(0xFFD5DCE6)
    ..strokeWidth = size.width / 450;

  switch (paper) {
    case Paper.blank:
      break;
    case Paper.ruled:
      final gap = size.height / 32;
      for (var y = gap * 2; y < size.height; y += gap) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
      canvas.drawLine(
        Offset(size.width * 0.12, 0),
        Offset(size.width * 0.12, size.height),
        Paint()
          ..color = const Color(0xFFF0B4B4)
          ..strokeWidth = size.width / 450,
      );
    case Paper.grid:
      final gap = size.width / 24;
      for (var x = gap; x < size.width; x += gap) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
      for (var y = gap; y < size.height; y += gap) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    case Paper.dots:
      final gap = size.width / 24;
      final dot = Paint()..color = const Color(0xFFB8C2D0);
      for (var x = gap; x < size.width; x += gap) {
        for (var y = gap; y < size.height; y += gap) {
          canvas.drawCircle(Offset(x, y), size.width / 380, dot);
        }
      }
  }
}

class _PaperPainter extends CustomPainter {
  final Paper paper;
  _PaperPainter(this.paper);

  @override
  void paint(Canvas canvas, Size size) => paintPaper(canvas, size, paper);

  @override
  bool shouldRepaint(_PaperPainter old) => old.paper != paper;
}

class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key});

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  static const _ratio = 1 / 1.414; // A4 dikey

  final _model = InkModel()..pen = true;
  Paper _paper = Paper.blank;
  bool _move = false; // true: kaydır / yakınlaştır
  Size _sheet = const Size(300, 424);
  bool _saved = true;

  @override
  void initState() {
    super.initState();
    _model.addListener(() {
      if (_saved && _model.hasInk) setState(() => _saved = false);
    });
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _toggleMove() {
    setState(() => _move = !_move);
    _model.update(() => _model.pen = !_move);
  }

  Future<Uint8List> _renderPng({double scale = 3}) async {
    final size = Size(_sheet.width * scale, _sheet.height * scale);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    paintPaper(canvas, size, _paper);
    paintInk(canvas, size, _model.of(1));
    final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  String get _stamp => '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

  Future<void> _savePng() async {
    final dir = await FileService.docsDir();
    final path = await FileService.uniquePath(dir.path, 'Cizim_$_stamp.png');
    await File(path).writeAsBytes(await _renderPng());
    await RecentStore.add(path);
    if (!mounted) return;
    setState(() => _saved = true);
    toast(context, 'Kaydedildi: ${p.basename(path)}');
  }

  Future<void> _savePdf() async {
    final png = await _renderPng(scale: 2.5);
    final doc = pw.Document();
    final image = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
    final dir = await FileService.docsDir();
    final path = await FileService.uniquePath(dir.path, 'Cizim_$_stamp.pdf');
    await File(path).writeAsBytes(await doc.save());
    await RecentStore.add(path);
    if (!mounted) return;
    setState(() => _saved = true);
    toast(context, 'Kaydedildi: ${p.basename(path)}');
  }

  Future<void> _share() async {
    final tmp = await getTemporaryDirectory();
    final path = p.join(tmp.path, 'Cizim_$_stamp.png');
    await File(path).writeAsBytes(await _renderPng());
    await Share.shareXFiles([XFile(path)]);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayfa temizlensin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Temizle')),
        ],
      ),
    );
    if (ok == true) _model.clearAll();
  }

  Future<void> _onBack() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çizim kaydedilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Kaydetme')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Kaydet')),
        ],
      ),
    );
    if (choice == null || choice == 'cancel') return;
    if (choice == 'save') await _savePng();
    if (!mounted) return;
    setState(() => _saved = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _saved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Çizim'),
          actions: [
            IconButton(
              tooltip: _move ? 'Çizim moduna geç' : 'Kaydır / yakınlaştır',
              isSelected: _move,
              style: _move
                  ? IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    )
                  : null,
              onPressed: _toggleMove,
              icon: const Icon(Icons.pan_tool_alt_rounded),
            ),
            PopupMenuButton<Paper>(
              tooltip: 'Kağıt',
              icon: const Icon(Icons.grid_4x4_rounded),
              initialValue: _paper,
              onSelected: (v) => setState(() => _paper = v),
              itemBuilder: (_) => [
                for (final e in _paperNames.entries)
                  PopupMenuItem(value: e.key, child: Text(e.value)),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'Kaydet ve paylaş',
              icon: const Icon(Icons.save_rounded),
              onSelected: (v) {
                if (!_model.hasInk && v != 'clear') {
                  toast(context, 'Önce bir şey çiz');
                  return;
                }
                switch (v) {
                  case 'png':
                    _savePng();
                  case 'pdf':
                    _savePdf();
                  case 'share':
                    _share();
                  case 'clear':
                    _confirmClear();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'png',
                  child: ListTile(
                    leading: Icon(Icons.image_rounded),
                    title: Text('Resim olarak kaydet'),
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf_rounded),
                    title: Text('PDF olarak kaydet'),
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.ios_share_rounded),
                    title: Text('Paylaş'),
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded),
                    title: Text('Sayfayı temizle'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFFE9ECF1),
                child: LayoutBuilder(
                  builder: (context, c) {
                    var w = c.maxWidth - 24;
                    var h = w / _ratio;
                    if (h > c.maxHeight - 24) {
                      h = c.maxHeight - 24;
                      w = h * _ratio;
                    }
                    _sheet = Size(w, h);
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      boundaryMargin: const EdgeInsets.all(60),
                      panEnabled: _move,
                      scaleEnabled: true,
                      child: Center(
                        child: Container(
                          width: w,
                          height: h,
                          decoration: BoxDecoration(
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(2, 2)),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(painter: _PaperPainter(_paper)),
                              ),
                              InkLayer(
                                model: _model,
                                page: 1,
                                size: Size(w, h),
                                onChanged: () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            InkToolbar(model: _model, onChanged: () {}),
          ],
        ),
      ),
    );
  }
}
