import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

// ───────────────────────── Araçlar ─────────────────────────

enum ToolKind { freehand, shape, eraser }

enum InkTool {
  ballpoint('Tükenmez', Icons.edit_rounded, 1.0, 1.0),
  fountain('Dolma', Icons.draw_rounded, 1.4, 1.0, pMin: 0.35, pMax: 1.6),
  brush('Fırça', Icons.brush_rounded, 2.4, 0.95, pMin: 0.2, pMax: 1.9),
  pencil('Kurşun', Icons.create_rounded, 0.9, 0.7),
  marker('Keçeli', Icons.border_color_rounded, 2.8, 0.85),
  highlighter('Fosforlu', Icons.highlight_rounded, 6.0, 0.35),
  dashed('Kesikli', Icons.more_horiz_rounded, 1.0, 1.0),
  line('Çizgi', Icons.horizontal_rule_rounded, 1.0, 1.0, kind: ToolKind.shape),
  arrow('Ok', Icons.arrow_right_alt_rounded, 1.0, 1.0, kind: ToolKind.shape),
  rect('Kutu', Icons.crop_square_rounded, 1.0, 1.0, kind: ToolKind.shape),
  ellipse('Elips', Icons.circle_outlined, 1.0, 1.0, kind: ToolKind.shape),
  eraser(
    'Silgi',
    Icons.auto_fix_normal_rounded,
    1.0,
    1.0,
    kind: ToolKind.eraser,
  );

  const InkTool(
    this.label,
    this.icon,
    this.widthMul,
    this.alpha, {
    this.kind = ToolKind.freehand,
    this.pMin = 0,
    this.pMax = 0,
  });

  final String label;
  final IconData icon;
  final double widthMul;
  final double alpha;
  final ToolKind kind;
  final double pMin; // baskı hassasiyeti: en ince çarpan
  final double pMax; // baskı hassasiyeti: en kalın çarpan

  bool get pressure => pMax > 0;
}

// ───────────────────────── Çizgi verisi ─────────────────────────

/// Noktalar sayfa boyutuna göre 0..1 arasındadır, kalınlık sayfa genişliğine
/// orandır. Böylece yakınlaştırma veya dışa aktarma boyutu fark etmez.
class InkStroke {
  final InkTool tool;
  final int color;
  final double width;
  final List<Offset> pts;
  final List<double> pressure;

  InkStroke({
    required this.tool,
    required this.color,
    required this.width,
    List<Offset>? pts,
    List<double>? pressure,
  }) : pts = pts ?? <Offset>[],
       pressure = pressure ?? <double>[];

  static double _r(double v) => (v * 10000).round() / 10000;

  Map<String, dynamic> toJson() => {
    'k': tool.name,
    'c': color,
    'w': _r(width),
    'p': [
      for (final o in pts) ...[_r(o.dx), _r(o.dy)],
    ],
    if (pressure.isNotEmpty)
      'q': [for (final v in pressure) (v * 100).round() / 100],
  };

  factory InkStroke.fromJson(Map<String, dynamic> j) {
    final f = (j['p'] as List).cast<num>();
    InkTool tool;
    if (j['k'] != null) {
      tool = InkTool.values.firstWhere(
        (t) => t.name == j['k'],
        orElse: () => InkTool.ballpoint,
      );
    } else {
      // Eski sürümde kaydedilmiş çizimler
      tool = (j['h'] == true) ? InkTool.highlighter : InkTool.ballpoint;
    }
    return InkStroke(
      tool: tool,
      color: (j['c'] as int) | 0xFF000000,
      width: (j['w'] as num).toDouble(),
      pts: [
        for (var i = 0; i + 1 < f.length; i += 2)
          Offset(f[i].toDouble(), f[i + 1].toDouble()),
      ],
      pressure: j['q'] == null
          ? null
          : (j['q'] as List).map((e) => (e as num).toDouble()).toList(),
    );
  }
}

// ───────────────────────── Çizim durumu ─────────────────────────

class _Action {
  final int page;
  final InkStroke stroke;
  final bool added; // true: eklendi, false: silindi
  _Action(this.page, this.stroke, this.added);
}

class InkModel extends ChangeNotifier {
  final Map<int, List<InkStroke>> strokes;
  final Map<int, int> _pageRevisions = {};
  InkModel([Map<int, List<InkStroke>>? initial]) : strokes = initial ?? {};

  bool pen = false; // true: kalem katmanı dokunuşları alır
  bool finger = true; // parmakla çizim varsayılan olarak açık
  InkTool tool = InkTool.ballpoint;
  Color color = const Color(0xFF14202F);
  double width = 3;

  final List<_Action> _history = [];
  final List<_Action> _redo = [];

  bool get canUndo => _history.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasInk => strokes.values.any((l) => l.isNotEmpty);
  int revisionForPage(int page) => _pageRevisions[page] ?? 0;

  void _markPageChanged(int page) {
    _pageRevisions.update(page, (revision) => revision + 1, ifAbsent: () => 1);
  }

  List<int> get inkPages =>
      (strokes.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => e.key)
          .toList()
        ..sort());

  List<InkStroke> of(int page) => strokes[page] ?? const [];

  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  void add(int page, InkStroke s) {
    (strokes[page] ??= []).add(s);
    _history.add(_Action(page, s, true));
    _redo.clear();
    _markPageChanged(page);
    notifyListeners();
  }

  bool eraseAt(int page, Offset local, Size size, double radius) {
    final list = strokes[page];
    if (list == null || list.isEmpty) return false;
    final hit = <InkStroke>[];
    for (final s in list) {
      final points = s.tool.kind == ToolKind.shape ? outlineOf(s) : s.pts;
      var near = false;
      if (points.length == 1) {
        final point = points.first;
        near =
            (Offset(point.dx * size.width, point.dy * size.height) - local)
                .distance <
            radius;
      } else {
        for (var i = 1; i < points.length; i++) {
          final previous = points[i - 1];
          final current = points[i];
          if (_segDist(
                local,
                Offset(previous.dx * size.width, previous.dy * size.height),
                Offset(current.dx * size.width, current.dy * size.height),
              ) <
              radius) {
            near = true;
            break;
          }
        }
      }
      if (near) hit.add(s);
    }
    if (hit.isEmpty) return false;
    for (final s in hit) {
      list.remove(s);
      _history.add(_Action(page, s, false));
    }
    _redo.clear();
    _markPageChanged(page);
    notifyListeners();
    return true;
  }

  void undo() {
    if (_history.isEmpty) return;
    final a = _history.removeLast();
    final list = strokes[a.page] ??= [];
    a.added ? list.remove(a.stroke) : list.add(a.stroke);
    _redo.add(a);
    _markPageChanged(a.page);
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final a = _redo.removeLast();
    final list = strokes[a.page] ??= [];
    a.added ? list.add(a.stroke) : list.remove(a.stroke);
    _history.add(a);
    _markPageChanged(a.page);
    notifyListeners();
  }

  void clearAll() {
    for (final page in strokes.keys) {
      _markPageChanged(page);
    }
    strokes.clear();
    _history.clear();
    _redo.clear();
    notifyListeners();
  }
}

double _segDist(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final ap = p - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / len2).clamp(0.0, 1.0).toDouble();
  return (p - (a + ab * t)).distance;
}

/// Silgi için çizginin (normalize) dış hattı.
List<Offset> outlineOf(InkStroke s) {
  if (s.tool.kind != ToolKind.shape || s.pts.length < 2) return s.pts;
  final a = s.pts.first;
  final b = s.pts.last;
  switch (s.tool) {
    case InkTool.rect:
      return [a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy), a];
    case InkTool.ellipse:
      final c = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final rx = (b.dx - a.dx).abs() / 2;
      final ry = (b.dy - a.dy).abs() / 2;
      return [
        for (var i = 0; i <= 32; i++)
          Offset(
            c.dx + rx * math.cos(i / 32 * 2 * math.pi),
            c.dy + ry * math.sin(i / 32 * 2 * math.pi),
          ),
      ];
    default:
      return [a, b];
  }
}

// ───────────────────────── Çizim (boyama) ─────────────────────────

void paintInk(Canvas canvas, Size size, Iterable<InkStroke> strokes) {
  for (final s in strokes) {
    _paintStroke(canvas, size, s);
  }
}

Path _smooth(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1];
    final b = pts[i];
    path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}

Path _dash(Path src, double dash, double gap) {
  final out = Path();
  for (final m in src.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
      d += dash + gap;
    }
  }
  return out;
}

void _paintStroke(Canvas canvas, Size size, InkStroke s) {
  if (s.pts.isEmpty || s.tool.kind == ToolKind.eraser) return;
  final tool = s.tool;
  final base = s.width * size.width;
  final color = Color(s.color | 0xFF000000).withValues(alpha: tool.alpha);
  final pts = [
    for (final o in s.pts) Offset(o.dx * size.width, o.dy * size.height),
  ];

  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = base
    ..strokeCap = tool == InkTool.highlighter ? StrokeCap.butt : StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  if (tool.kind == ToolKind.shape) {
    final a = pts.first;
    final b = pts.length > 1 ? pts.last : a;
    switch (tool) {
      case InkTool.line:
        canvas.drawLine(a, b, paint);
      case InkTool.arrow:
        canvas.drawLine(a, b, paint);
        final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
        final len = math.max(base * 4, size.width * 0.025);
        for (final d in [-0.5, 0.5]) {
          canvas.drawLine(
            b,
            b - Offset(math.cos(ang + d), math.sin(ang + d)) * len,
            paint,
          );
        }
      case InkTool.rect:
        canvas.drawRect(Rect.fromPoints(a, b), paint);
      case InkTool.ellipse:
        canvas.drawOval(Rect.fromPoints(a, b), paint);
      default:
        break;
    }
    return;
  }

  if (pts.length == 1) {
    canvas.drawCircle(pts.first, base / 2, paint..style = PaintingStyle.fill);
    return;
  }

  if (tool.pressure && s.pressure.length == pts.length) {
    for (var i = 1; i < pts.length; i++) {
      final pr = (s.pressure[i - 1] + s.pressure[i]) / 2;
      final f = tool.pMin + (tool.pMax - tool.pMin) * pr;
      canvas.drawLine(pts[i - 1], pts[i], paint..strokeWidth = base * f);
    }
    return;
  }

  final path = _smooth(pts);
  if (tool == InkTool.dashed) {
    canvas.drawPath(_dash(path, base * 3, base * 2.2), paint);
    return;
  }
  if (tool == InkTool.pencil) {
    canvas.drawPath(path, paint);
    canvas.save();
    canvas.translate(base * 0.25, base * 0.2);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: tool.alpha * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = base * 0.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
    return;
  }
  canvas.drawPath(path, paint);
}

class _InkPainter extends CustomPainter {
  final List<InkStroke> strokes;
  final int revision;

  _InkPainter(this.strokes, this.revision);

  @override
  void paint(Canvas canvas, Size size) => paintInk(canvas, size, strokes);

  @override
  bool shouldRepaint(_InkPainter old) => revision != old.revision;
}

class _LiveInkPainter extends CustomPainter {
  final InkStroke? stroke;
  final int revision;

  _LiveInkPainter(this.stroke, this.revision);

  @override
  void paint(Canvas canvas, Size size) {
    final current = stroke;
    if (current != null) paintInk(canvas, size, [current]);
  }

  @override
  bool shouldRepaint(_LiveInkPainter old) => revision != old.revision;
}

// ───────────────────────── Sayfa katmanı ─────────────────────────

/// Bir sayfanın üstündeki çizim katmanı. Hem PDF hem boş çizim kağıdı için.
class InkLayer extends StatefulWidget {
  final InkModel model;
  final int page;
  final Size size;
  final VoidCallback onChanged;

  const InkLayer({
    super.key,
    required this.model,
    required this.page,
    required this.size,
    required this.onChanged,
  });

  @override
  State<InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<InkLayer> {
  int? _pointer;
  InkStroke? _live;
  double _lastP = 0.5;
  int _liveRevision = 0;

  bool _accept(PointerEvent e) {
    switch (e.kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
      case PointerDeviceKind.mouse:
        return true;
      case PointerDeviceKind.touch:
        return widget.model.finger;
      default:
        return false;
    }
  }

  Offset _norm(PointerEvent e) => Offset(
    (e.localPosition.dx / widget.size.width).clamp(0.0, 1.0),
    (e.localPosition.dy / widget.size.height).clamp(0.0, 1.0),
  );

  double _pressure(PointerEvent e) {
    final min = e.pressureMin;
    final max = e.pressureMax;
    if (max <= min) return 0.5;
    final raw = ((e.pressure - min) / (max - min)).clamp(0.0, 1.0).toDouble();
    _lastP = _lastP * 0.6 + raw * 0.4; // yumuşat
    return _lastP;
  }

  bool _erasing(PointerEvent e) =>
      widget.model.tool.kind == ToolKind.eraser ||
      e.kind == PointerDeviceKind.invertedStylus;

  void _erase(PointerEvent e) {
    final r = 8 + widget.model.width * 1.5;
    if (widget.model.eraseAt(widget.page, e.localPosition, widget.size, r)) {
      widget.onChanged();
    }
  }

  void _down(PointerDownEvent e) {
    if (!_accept(e) || _pointer != null) return;
    _pointer = e.pointer;
    if (_erasing(e)) {
      _erase(e);
      return;
    }
    final m = widget.model;
    _lastP = 0.5;
    final stroke = InkStroke(
      tool: m.tool,
      color: m.color.toARGB32() | 0xFF000000,
      width: (m.width * m.tool.widthMul) / widget.size.width,
    )..pts.add(_norm(e));
    if (m.tool.pressure) stroke.pressure.add(_pressure(e));
    setState(() {
      _live = stroke;
      _liveRevision++;
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_erasing(e)) {
      _erase(e);
      return;
    }
    final s = _live;
    if (s == null) return;
    setState(() {
      if (s.tool.kind == ToolKind.shape) {
        if (s.pts.length == 1) {
          s.pts.add(_norm(e));
        } else {
          s.pts[1] = _norm(e);
        }
      } else {
        s.pts.add(_norm(e));
        if (s.tool.pressure) s.pressure.add(_pressure(e));
      }
      _liveRevision++;
    });
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final s = _live;
    if (s == null) return;
    _live = null;
    final isShapeTap = s.tool.kind == ToolKind.shape && s.pts.length < 2;
    if (!isShapeTap) {
      widget.model.add(widget.page, s);
      widget.onChanged();
    }
    setState(() => _liveRevision++);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        return SizedBox(
          width: widget.size.width,
          height: widget.size.height,
          child: IgnorePointer(
            ignoring: !widget.model.pen,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: widget.size,
                      painter: _InkPainter(
                        widget.model.of(widget.page),
                        widget.model.revisionForPage(widget.page),
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      size: widget.size,
                      painter: _LiveInkPainter(_live, _liveRevision),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── Araç çubuğu ─────────────────────────

const inkPalette = <Color>[
  Color(0xFF14202F),
  Color(0xFF5A6B7F),
  Color(0xFFD64545),
  Color(0xFFE91E63),
  Color(0xFFDD6B20),
  Color(0xFFFFB300),
  Color(0xFFFFD60A),
  Color(0xFF8BC34A),
  Color(0xFF2F855A),
  Color(0xFF00ACC1),
  Color(0xFF2B6CB0),
  Color(0xFF3949AB),
  Color(0xFF7B5EA7),
  Color(0xFF8D6E63),
  Color(0xFFFFFFFF),
];

Future<Color?> pickInkColor(BuildContext context, Color initial) {
  return showModalBottomSheet<Color>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      var hsv = HSVColor.fromColor(initial);
      return StatefulBuilder(
        builder: (ctx, setS) {
          final c = hsv.toColor();
          Widget slider(
            String label,
            double v,
            double max,
            ValueChanged<double> f,
          ) => Row(
            children: [
              SizedBox(width: 78, child: Text(label)),
              Expanded(
                child: Slider(value: v, min: 0, max: max, onChanged: f),
              ),
            ],
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Pal.of(ctx).border),
                    ),
                  ),
                  slider(
                    'Renk tonu',
                    hsv.hue,
                    360,
                    (v) => setS(() => hsv = hsv.withHue(v)),
                  ),
                  slider(
                    'Canlılık',
                    hsv.saturation,
                    1,
                    (v) => setS(() => hsv = hsv.withSaturation(v)),
                  ),
                  slider(
                    'Koyuluk',
                    hsv.value,
                    1,
                    (v) => setS(() => hsv = hsv.withValue(v)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, c),
                      child: const Text('Tamam'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class InkToolbar extends StatefulWidget {
  final InkModel model;
  final VoidCallback onChanged; // geri al / ileri al sonrası kaydetmek için
  final List<Widget> extra;

  const InkToolbar({
    super.key,
    required this.model,
    required this.onChanged,
    this.extra = const [],
  });

  @override
  State<InkToolbar> createState() => _InkToolbarState();
}

class _InkToolbarState extends State<InkToolbar> {
  static const _quickTools = [
    InkTool.ballpoint,
    InkTool.highlighter,
    InkTool.pencil,
    InkTool.eraser,
  ];
  static const _otherTools = [
    InkTool.fountain,
    InkTool.brush,
    InkTool.marker,
    InkTool.dashed,
    InkTool.line,
    InkTool.arrow,
    InkTool.rect,
    InkTool.ellipse,
  ];

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final scheme = Theme.of(context).colorScheme;
    final pal = Pal.of(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: pal.card,
          border: Border(top: BorderSide(color: pal.border)),
        ),
        child: ListenableBuilder(
          listenable: m,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 58,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final tool in _quickTools)
                        _quickTool(tool, m, scheme),
                      const VerticalDivider(
                        width: 14,
                        indent: 12,
                        endIndent: 12,
                      ),
                      TextButton.icon(
                        onPressed: () => _chooseTool(m),
                        icon: Icon(m.tool.icon, size: 18),
                        label: Text(
                          _quickTools.contains(m.tool) ? 'Diğer' : m.tool.label,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Renk seç',
                        onPressed: () async {
                          final color = await pickInkColor(context, m.color);
                          if (color != null) {
                            m.update(() {
                              m.color = color;
                              if (m.tool.kind == ToolKind.eraser) {
                                m.tool = InkTool.ballpoint;
                              }
                            });
                          }
                        },
                        icon: _colorPreview(m),
                      ),
                      IconButton(
                        tooltip: 'Geri al',
                        onPressed: m.canUndo
                            ? () {
                                m.undo();
                                widget.onChanged();
                              }
                            : null,
                        icon: const Icon(Icons.undo_rounded),
                      ),
                      IconButton(
                        tooltip: 'İleri al',
                        onPressed: m.canRedo
                            ? () {
                                m.redo();
                                widget.onChanged();
                              }
                            : null,
                        icon: const Icon(Icons.redo_rounded),
                      ),
                      IconButton(
                        tooltip: _expanded
                            ? 'Ayarları gizle'
                            : 'Kalem ayarları',
                        onPressed: () => setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.tune_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_expanded) ...[
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final c in inkPalette) _swatch(c, m, scheme),
                        _customColor(m),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 34, child: _sizePreview(m)),
                        const SizedBox(width: 8),
                        const Text('Kalınlık'),
                        Expanded(
                          child: Slider(
                            value: m.width,
                            min: 1,
                            max: 24,
                            onChanged: (v) => m.update(() => m.width = v),
                          ),
                        ),
                        Text(
                          '${m.width.round()}',
                          style: TextStyle(color: pal.muted),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => m.update(() => m.finger = !m.finger),
                      icon: Icon(
                        m.finger
                            ? Icons.touch_app_rounded
                            : Icons.pan_tool_alt_rounded,
                      ),
                      label: Text(
                        m.finger ? 'Parmakla çizim açık' : 'Parmakla çizim',
                      ),
                    ),
                  ),
                ],
                if (widget.extra.isNotEmpty)
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: widget.extra,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _quickTool(InkTool t, InkModel m, ColorScheme scheme) {
    final sel = m.tool == t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: IconButton(
        tooltip: t.label,
        isSelected: sel,
        style: IconButton.styleFrom(
          backgroundColor: sel ? scheme.primary : Colors.transparent,
          foregroundColor: sel ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
        onPressed: () => m.update(() => m.tool = t),
        icon: Icon(t.icon),
      ),
    );
  }

  Future<void> _chooseTool(InkModel model) async {
    final selected = await showModalBottomSheet<InkTool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Kalemler',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final tool in _otherTools.where(
              (tool) => tool.kind == ToolKind.freehand,
            ))
              _toolListTile(tool, model),
            const ListTile(
              title: Text(
                'Şekiller',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final tool in _otherTools.where(
              (tool) => tool.kind == ToolKind.shape,
            ))
              _toolListTile(tool, model),
          ],
        ),
      ),
    );
    if (selected != null) model.update(() => model.tool = selected);
  }

  Widget _toolListTile(InkTool tool, InkModel model) => ListTile(
    leading: Icon(tool.icon),
    title: Text(tool.label),
    trailing: model.tool == tool ? const Icon(Icons.check_rounded) : null,
    onTap: () => Navigator.pop(context, tool),
  );

  Widget _colorPreview(InkModel model) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: model.color,
        shape: BoxShape.circle,
        border: Border.all(color: Pal.of(context).border, width: 2),
      ),
    );
  }

  Widget _swatch(Color c, InkModel m, ColorScheme scheme) {
    final sel = m.color.toARGB32() == c.toARGB32();
    return GestureDetector(
      onTap: () => m.update(() {
        m.color = c;
        if (m.tool.kind == ToolKind.eraser) m.tool = InkTool.ballpoint;
      }),
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 8, top: 3, bottom: 3),
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: sel ? scheme.primary : Pal.of(context).border,
            width: sel ? 3 : 1,
          ),
        ),
      ),
    );
  }

  Widget _customColor(InkModel m) {
    return GestureDetector(
      onTap: () async {
        final c = await pickInkColor(context, m.color);
        if (c != null) {
          m.update(() {
            m.color = c;
            if (m.tool.kind == ToolKind.eraser) m.tool = InkTool.ballpoint;
          });
        }
      },
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 8, top: 3, bottom: 3),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
          ),
        ),
        child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
      ),
    );
  }

  Widget _sizePreview(InkModel m) {
    final pal = Pal.of(context);
    final d = (m.width * m.tool.widthMul).clamp(2.0, 38.0).toDouble();
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: m.tool.kind == ToolKind.eraser
            ? pal.border
            : m.color.withValues(alpha: m.tool.alpha),
        shape: BoxShape.circle,
        border: Border.all(color: pal.muted),
      ),
    );
  }
}
