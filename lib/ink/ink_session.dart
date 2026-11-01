import 'package:flutter/material.dart';

import '../services/annotation_store.dart';
import 'ink_core.dart';

/// Herhangi bir belge ekranına kalem katmanı eklemek için ortak yardımcı.
/// Çizimler dosyaya dokunmadan uygulamanın kendi klasörüne (AnnotationStore)
/// otomatik kaydedilir, dosya yoluna göre geri yüklenir.
class InkSession {
  final String path;
  final InkModel model = InkModel();
  bool pen = false;
  bool _colorSet = false;

  InkSession(this.path) {
    _load();
  }

  Future<void> _load() async {
    final saved = await AnnotationStore.load(path);
    if (saved.isEmpty) return;
    model.update(() => model.strokes.addAll(saved));
  }

  void save() => AnnotationStore.save(path, model.strokes);

  void dispose() => model.dispose();

  /// Karanlık temada varsayılan kalem rengi açık olsun.
  void adaptColor(BuildContext context) {
    if (_colorSet) return;
    _colorSet = true;
    if (Theme.of(context).brightness == Brightness.dark) {
      model.color = const Color(0xFFFFD60A);
    }
  }

  void toggle() {
    pen = !pen;
    model.update(() => model.pen = pen);
  }

  /// Parmakla çizerken kaydırma kapanır.
  ScrollPhysics? get physics =>
      (pen && model.finger) ? const NeverScrollableScrollPhysics() : null;

  Widget watch(Widget Function() build) =>
      ListenableBuilder(listenable: model, builder: (_, __) => build());

  /// [child]'ın üstüne çizim katmanı koyar. Katman child'ın boyutunu alır,
  /// içerikle birlikte kayar.
  Widget overlay({required int page, required Widget child}) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: LayoutBuilder(
            builder: (_, c) => InkLayer(
              key: ValueKey('ink-$page'),
              model: model,
              page: page,
              size: c.biggest,
              onChanged: save,
            ),
          ),
        ),
      ],
    );
  }

  Widget penButton(BuildContext context, VoidCallback refresh) {
    return IconButton(
      tooltip: pen ? 'Kaydırma moduna geç' : 'Kalemle yaz / çiz',
      isSelected: pen,
      style: pen
          ? IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      onPressed: () {
        toggle();
        refresh();
      },
      icon: const Icon(Icons.draw_rounded),
    );
  }

  Widget toolbar(BuildContext context, VoidCallback refresh) {
    return ListenableBuilder(
      listenable: model,
      builder: (ctx, _) => InkToolbar(
        model: model,
        onChanged: save,
        extra: [
          IconButton(
            tooltip: 'Çizimleri sil',
            onPressed: model.hasInk ? () => _confirmClear(ctx) : null,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm çizimler silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      model.clearAll();
      save();
    }
  }
}
