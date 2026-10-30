import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../services/file_service.dart';
import '../services/recent_store.dart';
import '../widgets/common.dart';

enum _Tool { pen, marker, eraser }

class _Stroke {
  final List<Offset> pts = [];
  final Color color;
  final double width;
  _Stroke(this.color, this.width);
}

class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key});

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  final _strokes = <_Stroke>[];
  final _redo = <_Stroke>[];
  final _key = GlobalKey();

  _Tool _tool = _Tool.pen;
  Color _color = const Color(0xFF14202F);
  double _width = 4;
  String? _savedPath;

  static const _palette = [
    Color(0xFF14202F),
    Color(0xFFD64545),
    Color(0xFFDD6B20),
    Color(0xFF2F855A),
    Color(0xFF2B6CB0),
    Color(0xFF7B5EA7),
  ];

  _Stroke _newStroke() {
    switch (_tool) {
      case _Tool.pen:
        return _Stroke(_color, _width);
      case _Tool.marker:
        return _Stroke(_color.withValues(alpha: 0.35), _width * 4);
      case _Tool.eraser:
        return _Stroke(Colors.white, _width * 4);
    }
  }

  Future<String?> _save() async {
    final boundary =
        _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final dir = await FileService.docsDir();
    final path = _savedPath ??
        await FileService.uniquePath(
          dir.path,
          'Cizim_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.png',
        );
    await File(path).writeAsBytes(data.buffer.asUint8List());
    await RecentStore.add(path);
    _savedPath = path;
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Çizim'),
        actions: [
          IconButton(
            tooltip: 'Geri al',
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _redo.add(_strokes.removeLast())),
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'İleri al',
            onPressed: _redo.isEmpty
                ? null
                : () => setState(() => _strokes.add(_redo.removeLast())),
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            tooltip: 'Temizle',
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() {
                      _strokes.clear();
                      _redo.clear();
                    }),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            tooltip: 'Paylaş',
            onPressed: _strokes.isEmpty
                ? null
                : () async {
                    final path = await _save();
                    if (path != null) await Share.shareXFiles([XFile(path)]);
                  },
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Kaydet',
            onPressed: _strokes.isEmpty
                ? null
                : () async {
                    final path = await _save();
                    if (mounted && path != null) toast(context, 'Kaydedildi');
                  },
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E6EC)),
              ),
              clipBehavior: Clip.antiAlias,
              child: RepaintBoundary(
                key: _key,
                child: GestureDetector(
                  onPanStart: (d) => setState(() {
                    _redo.clear();
                    _strokes.add(_newStroke()..pts.add(d.localPosition));
                  }),
                  onPanUpdate: (d) =>
                      setState(() => _strokes.last.pts.add(d.localPosition)),
                  child: CustomPaint(
                    painter: _Painter(_strokes),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          _toolbar(),
        ],
      ),
    );
  }

  Widget _toolbar() {
    final scheme = Theme.of(context).colorScheme;
    Widget toolBtn(_Tool t, IconData icon, String tip) => IconButton.filledTonal(
          tooltip: tip,
          isSelected: _tool == t,
          style: IconButton.styleFrom(
            backgroundColor:
                _tool == t ? scheme.primary : scheme.surfaceContainerHighest,
            foregroundColor: _tool == t ? Colors.white : scheme.onSurface,
          ),
          onPressed: () => setState(() => _tool = t),
          icon: Icon(icon),
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                toolBtn(_Tool.pen, Icons.edit_rounded, 'Kalem'),
                const SizedBox(width: 8),
                toolBtn(_Tool.marker, Icons.highlight_rounded, 'Vurgulayıcı'),
                const SizedBox(width: 8),
                toolBtn(_Tool.eraser, Icons.auto_fix_normal_rounded, 'Silgi'),
                const SizedBox(width: 16),
                Expanded(
                  child: Slider(
                    value: _width,
                    min: 1,
                    max: 16,
                    onChanged: (v) => setState(() => _width = v),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => setState(() {
                      _color = c;
                      if (_tool == _Tool.eraser) _tool = _Tool.pen;
                    }),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c ? scheme.primary : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  final List<_Stroke> strokes;
  _Painter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (s.pts.length == 1) {
        canvas.drawCircle(
          s.pts.first,
          s.width / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      final path = Path()..moveTo(s.pts.first.dx, s.pts.first.dy);
      for (var i = 1; i < s.pts.length; i++) {
        final a = s.pts[i - 1];
        final b = s.pts[i];
        path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      }
      path.lineTo(s.pts.last.dx, s.pts.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
