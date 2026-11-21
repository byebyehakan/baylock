import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A compact, touch-friendly position scrubber for long documents.
class QuickScrollRail extends StatelessWidget {
  final ScrollController? controller;
  final int? pageCount;
  final int? currentPage;
  final ValueChanged<int>? onPageSelected;

  const QuickScrollRail({
    super.key,
    this.controller,
    this.pageCount,
    this.currentPage,
    this.onPageSelected,
  }) : assert(
         controller != null ||
             (pageCount != null &&
                 currentPage != null &&
                 onPageSelected != null),
       );

  @override
  Widget build(BuildContext context) {
    if (pageCount case final count?) {
      final page = currentPage ?? 1;
      if (count <= 10) return const SizedBox.shrink();
      return _Rail(
        count: count,
        page: page.clamp(1, count).toInt(),
        onSelected: onPageSelected!,
      );
    }
    return _ScrollableRail(controller: controller!);
  }
}

class _ScrollableRail extends StatefulWidget {
  final ScrollController controller;
  const _ScrollableRail({required this.controller});

  @override
  State<_ScrollableRail> createState() => _ScrollableRailState();
}

class _ScrollableRailState extends State<_ScrollableRail> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _ScrollableRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onScroll);
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.hasClients) return const SizedBox.shrink();
    final position = controller.position;
    if (!position.hasContentDimensions ||
        position.viewportDimension <= 0 ||
        position.maxScrollExtent <= 0) {
      return const SizedBox.shrink();
    }
    final viewport = position.viewportDimension;
    final count = (position.maxScrollExtent / viewport).ceil() + 1;
    if (count <= 10) return const SizedBox.shrink();
    final page = (position.pixels / viewport).floor() + 1;
    return _Rail(
      count: count,
      page: page.clamp(1, count).toInt(),
      onSelected: (selectedPage) {
        controller.animateTo(
          math.min((selectedPage - 1) * viewport, position.maxScrollExtent),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      },
    );
  }
}

class _Rail extends StatefulWidget {
  final int count;
  final int page;
  final ValueChanged<int> onSelected;

  const _Rail({
    required this.count,
    required this.page,
    required this.onSelected,
  });

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  static const _visibilityDuration = Duration(milliseconds: 900);
  static const _fadeDuration = Duration(milliseconds: 150);

  Timer? _hideTimer;
  bool _visible = false;

  @override
  void didUpdateWidget(covariant _Rail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) _showThumb();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showThumb() {
    _hideTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hideTimer = Timer(_visibilityDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Konum: ${widget.page} / ${widget.count}',
      slider: true,
      value: '${widget.page} / ${widget.count}',
      child: SizedBox(
        width: 28,
        height: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const thumbHeight = 28.0;
            final maxTop = constraints.maxHeight - thumbHeight;
            final top = (widget.page - 1) / (widget.count - 1) * maxTop;
            void selectAt(double dy) {
              _showThumb();
              final progress = (dy / constraints.maxHeight).clamp(0.0, 1.0);
              widget.onSelected((progress * (widget.count - 1)).round() + 1);
            }

            return IgnorePointer(
              ignoring: !_visible,
              child: GestureDetector(
                key: const Key('quick-scroll-rail'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => selectAt(details.localPosition.dy),
                onVerticalDragUpdate: (details) =>
                    selectAt(details.localPosition.dy),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: top,
                      child: AnimatedOpacity(
                        key: const Key('quick-scroll-thumb'),
                        opacity: _visible ? 1 : 0,
                        duration: _fadeDuration,
                        curve: Curves.easeOut,
                        child: Container(
                          width: 8,
                          height: thumbHeight,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
