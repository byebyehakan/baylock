import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ink/ink_session.dart';
import '../models/pptx_presentation.dart';
import '../services/pptx_service.dart';
import '../widgets/common.dart';
import '../widgets/document_tool_dock.dart';

class SlidesScreen extends StatefulWidget {
  final String path;
  const SlidesScreen({super.key, required this.path});

  @override
  State<SlidesScreen> createState() => _SlidesScreenState();
}

class _SlidesScreenState extends State<SlidesScreen> {
  late final Future<PptxPresentation> _future = PptxService.load(widget.path);
  final _controller = PageController();
  final _thumbnailsController = ScrollController();
  late final InkSession _ink = InkSession(widget.path);
  int _page = 0;
  bool _fullscreen = false;

  @override
  void dispose() {
    if (_fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _controller.dispose();
    _thumbnailsController.dispose();
    _ink.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _toggleFullscreen() async {
    final enterFullscreen = !_fullscreen;
    setState(() => _fullscreen = enterFullscreen);
    await SystemChrome.setEnabledSystemUIMode(
      enterFullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _page = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_thumbnailsController.hasClients) return;
      final position = _thumbnailsController.position;
      final target = (index * 92 - (position.viewportDimension - 92) / 2).clamp(
        0.0,
        position.maxScrollExtent,
      );
      _thumbnailsController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _goToPage(int page) {
    if (!_controller.hasClients) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    _ink.adaptColor(context);
    return Scaffold(
      appBar: _fullscreen
          ? null
          : AppBar(
              title: Text(
                fileTitle(widget.path),
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                ...fileActions(context, widget.path),
              ],
            ),
      body: FutureBuilder<PptxPresentation>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const _SlidesErrorBox(
              'Bu sunum açılamadı. Dosyanın bozuk olmadığını kontrol et veya sağ üstten başka uygulamada aç.',
            );
          }
          final presentation = snapshot.data!;
          return DocumentToolDock(
            model: _ink.model,
            onFullscreen: _toggleFullscreen,
            child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousSlideIntent(),
              SingleActivator(LogicalKeyboardKey.arrowRight): _NextSlideIntent(),
            },
            child: Actions(
              actions: {
                _PreviousSlideIntent: CallbackAction<_PreviousSlideIntent>(
                  onInvoke: (_) {
                    if (_page > 0) _goToPage(_page - 1);
                    return null;
                  },
                ),
                _NextSlideIntent: CallbackAction<_NextSlideIntent>(
                  onInvoke: (_) {
                    if (_page + 1 < presentation.slides.length) {
                      _goToPage(_page + 1);
                    }
                    return null;
                  },
                ),
              },
              child: Focus(
                autofocus: true,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _ink.watch(
                        () => PageView.builder(
                          controller: _controller,
                          physics: _ink.physics,
                          itemCount: presentation.slides.length,
                          onPageChanged: _onPageChanged,
                          itemBuilder: (_, index) => _SlideReaderPage(
                            page: index + 1,
                            slide: presentation.slides[index],
                            presentation: presentation,
                            ink: _ink,
                          ),
                        ),
                      ),
                    ),
              if (_fullscreen)
                Positioned(
                  top: 8,
                  right: 8,
                  child: SafeArea(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FullscreenButton(
                          tooltip: _ink.pen ? 'Çizim açık' : 'Kalemle çiz',
                          onPressed: () {
                            _ink.toggle();
                            _refresh();
                          },
                          icon: Icons.draw_rounded,
                          selected: _ink.pen,
                        ),
                        const SizedBox(width: 8),
                        _FullscreenButton(
                          tooltip: 'Tam ekrandan çık',
                          onPressed: _toggleFullscreen,
                          icon: Icons.fullscreen_exit_rounded,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_ink.pen) _ink.toolbar(context, _refresh),
                      _SlideNavigationBar(
                        currentPage: _page,
                        pageCount: presentation.slides.length,
                        onPrevious: _page == 0
                            ? null
                            : () => _goToPage(_page - 1),
                        onNext: _page + 1 == presentation.slides.length
                            ? null
                            : () => _goToPage(_page + 1),
                      ),
                      _SlideFilmstrip(
                        slides: presentation.slides,
                        presentation: presentation,
                        controller: _thumbnailsController,
                        currentPage: _page,
                        onSelected: _goToPage,
                      ),
                    ],
                  ),
                ),
              if (_fullscreen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_ink.pen) _ink.toolbar(context, _refresh),
                      _SlideNavigationBar(
                        currentPage: _page,
                        pageCount: presentation.slides.length,
                        onPrevious: _page == 0
                            ? null
                            : () => _goToPage(_page - 1),
                        onNext: _page + 1 == presentation.slides.length
                            ? null
                            : () => _goToPage(_page + 1),
                      ),
                    ],
                  ),
                ),
                  ],
                ),
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}

class _FullscreenButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final bool selected;

  const _FullscreenButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        isSelected: selected,
        icon: Icon(icon),
      ),
    );
  }
}

class _PreviousSlideIntent extends Intent {
  const _PreviousSlideIntent();
}

class _NextSlideIntent extends Intent {
  const _NextSlideIntent();
}

class _SlideReaderPage extends StatelessWidget {
  final int page;
  final PptxSlide slide;
  final PptxPresentation presentation;
  final InkSession ink;

  const _SlideReaderPage({
    required this.page,
    required this.slide,
    required this.presentation,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) => InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      panEnabled: !ink.pen,
      scaleEnabled: !ink.pen,
      boundaryMargin: const EdgeInsets.all(80),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AspectRatio(
            aspectRatio: presentation.width / presentation.height,
            child: ink.overlay(
              page: page,
              child: _SlideCanvas(slide: slide, presentation: presentation),
            ),
          ),
        ),
      ),
    );
}

class _SlideNavigationBar extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _SlideNavigationBar({
    required this.currentPage,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Önceki slayt',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Semantics(
            liveRegion: true,
            label: 'Slayt ${currentPage + 1} / $pageCount',
            child: Text(
              'Slayt ${currentPage + 1} / $pageCount',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          IconButton(
            tooltip: 'Sonraki slayt',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    ),
  );
}

class _SlideFilmstrip extends StatelessWidget {
  final List<PptxSlide> slides;
  final PptxPresentation presentation;
  final ScrollController controller;
  final int currentPage;
  final ValueChanged<int> onSelected;

  const _SlideFilmstrip({
    required this.slides,
    required this.presentation,
    required this.controller,
    required this.currentPage,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.96),
      child: SizedBox(
        height: 64,
        child: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemExtent: 72,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          itemCount: slides.length,
          itemBuilder: (context, index) {
            final selected = index == currentPage;
            return Semantics(
              button: true,
              selected: selected,
              label: 'Slayt ${index + 1}',
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      
                      color: selected ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: _SlideCanvas(
                            slide: slides[index],
                            presentation: presentation,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 9,
                          height: 1,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SlideCanvas extends StatelessWidget {
  final PptxSlide slide;
  final PptxPresentation presentation;

  const _SlideCanvas({required this.slide, required this.presentation});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 960,
        height: presentation.height * 960 / presentation.width,
        child: ColoredBox(
          color: slide.background ?? Colors.white,
          child: Stack(
            children: [
              for (final element in slide.elements)
                _ElementView(element: element),
            ],
          ),
        ),
      ),
    );
  }
}

class _ElementView extends StatelessWidget {
  final PptxElement element;
  const _ElementView({required this.element});

  @override
  Widget build(BuildContext context) {
    final borderRadius = switch (element.geometry) {
      'ellipse' => BorderRadius.circular(1000),
      'roundRect' => BorderRadius.circular(12),
      _ => BorderRadius.zero,
    };
    final decoration = BoxDecoration(
      color: element.fill,
      borderRadius: borderRadius,
      border: element.line == null ? null : Border.all(color: element.line!),
    );
    Widget content;
    if (element.image != null) {
      content = Image.memory(
        element.image!,
        width: element.bounds.width,
        height: element.bounds.height,
        fit: BoxFit.fill,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
      );
    } else {
      content = Container(
        width: element.bounds.width,
        height: element.bounds.height,
        padding: element.textInsets,
        alignment: element.verticalCenter
            ? Alignment.centerLeft
            : Alignment.topLeft,
        decoration: decoration,
        child: element.paragraphs.isEmpty
            ? null
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: element.verticalCenter
                    ? Alignment.centerLeft
                    : Alignment.topLeft,
                child: SizedBox(
                  width: element.bounds.width - element.textInsets.horizontal,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: element.verticalCenter
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final paragraph in element.paragraphs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (paragraph.bullet)
                                  const TextSpan(
                                    text: '•  ',
                                    style: TextStyle(color: Color(0xFF202124)),
                                  ),
                                for (final run in paragraph.runs)
                                  TextSpan(
                                    text: run.text,
                                    style: TextStyle(
                                      color:
                                          run.color ?? const Color(0xFF202124),
                                      fontSize: run.fontSize ?? 18,
                                      fontWeight: run.bold
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontStyle: run.italic
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                      decoration: run.underline
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                                  ),
                              ],
                            ),
                            textAlign: paragraph.alignment,
                            softWrap: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      );
    }
    return Positioned.fromRect(
      rect: element.bounds,
      child: DecoratedBox(
        decoration: decoration,
        child: ClipRRect(borderRadius: borderRadius, child: content),
      ),
    );
  }
}

class _SlidesErrorBox extends StatelessWidget {
  final String message;
  const _SlidesErrorBox(this.message);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
