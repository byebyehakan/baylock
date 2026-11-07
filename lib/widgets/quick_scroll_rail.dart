import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
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

class _Rail extends StatelessWidget {
  final int count;
  final int page;
  final ValueChanged<int> onSelected;

  const _Rail({
    required this.count,
    required this.page,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.9),
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Hızlıca yukarı git',
              visualDensity: VisualDensity.compact,
              onPressed: page > 1
                  ? () => onSelected((page - 5).clamp(1, count).toInt())
                  : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            SizedBox(
              width: 28,
              height: 100,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxTop = constraints.maxHeight - 14;
                  final top = (page - 1) / (count - 1) * maxTop;
                  void selectAt(double dy) {
                    final progress = (dy / constraints.maxHeight).clamp(
                      0.0,
                      1.0,
                    );
                    onSelected((progress * (count - 1)).round() + 1);
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => selectAt(details.localPosition.dy),
                    onVerticalDragUpdate: (details) =>
                        selectAt(details.localPosition.dy),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Positioned(
                          top: top,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorScheme.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Text('$page/$count', style: Theme.of(context).textTheme.labelSmall),
            IconButton(
              tooltip: 'Hızlıca aşağı git',
              visualDensity: VisualDensity.compact,
              onPressed: page < count
                  ? () => onSelected((page + 5).clamp(1, count).toInt())
                  : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
