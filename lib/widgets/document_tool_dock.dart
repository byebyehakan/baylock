import 'package:flutter/material.dart';

import '../ink/ink_core.dart';

/// Session-only document tool dock. It always snaps to a top screen edge and
/// disappears with the viewer that owns it.
class DocumentToolDock extends StatefulWidget {
  final Widget child;
  final InkModel model;
  final VoidCallback? onFullscreen;

  const DocumentToolDock({
    super.key,
    required this.child,
    required this.model,
    this.onFullscreen,
  });

  @override
  State<DocumentToolDock> createState() => _DocumentToolDockState();
}

class _DocumentToolDockState extends State<DocumentToolDock> {
  bool _left = false;
  bool _open = false;
  double _top = 12;
  Offset? _lastGlobalPosition;

  void _togglePen() {
    widget.model.update(() => widget.model.pen = !widget.model.pen);
  }

  void _select(InkTool tool) {
    widget.model.update(() {
      widget.model
        ..tool = tool
        ..pen = true;
    });
    setState(() => _open = false);
  }

  Future<void> _showTools() async {
    final tool = await showModalBottomSheet<InkTool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tool in InkTool.values)
                ChoiceChip(
                  avatar: Icon(tool.icon, size: 18),
                  label: Text(tool.label),
                  selected: widget.model.tool == tool,
                  onSelected: (_) => Navigator.pop(context, tool),
                ),
            ],
          ),
        ),
      ),
    );
    if (tool != null && mounted) _select(tool);
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned(
        top: _top,
        left: _left ? -8 : null,
        right: _left ? null : -8,
        child: SafeArea(
          bottom: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: ListenableBuilder(
              listenable: widget.model,
              builder: (context, _) {
                final main = _DockButton(
                  tooltip: 'Çizim araçları',
                  selected: _open,
                  icon: widget.model.pen
                      ? widget.model.tool.icon
                      : Icons.edit_note_rounded,
                  onPressed: () => setState(() => _open = !_open),
                  onPanStart: (details) {
                    _lastGlobalPosition = details.globalPosition;
                  },
                  onPanUpdate: (details) {
                    final previous = _lastGlobalPosition;
                    _lastGlobalPosition = details.globalPosition;
                    if (previous == null) return;
                    final height = MediaQuery.sizeOf(context).height;
                    setState(() {
                      _top = (_top + details.globalPosition.dy - previous.dy)
                          .clamp(12.0, height - 68.0)
                          .toDouble();
                    });
                  },
                  onPanEnd: (_) {
                    final position = _lastGlobalPosition;
                    final width = MediaQuery.sizeOf(context).width;
                    if (position != null) {
                      setState(() => _left = position.dx < width / 2);
                    }
                    _lastGlobalPosition = null;
                  },
                );
                final tools = [
                  _DockButton(
                    tooltip: widget.model.pen ? 'Çizimi kapat' : 'Çizimi aç',
                    selected: widget.model.pen,
                    icon: Icons.draw_rounded,
                    onPressed: _togglePen,
                  ),
                  _DockButton(
                    tooltip: 'Kalem seç',
                    icon: Icons.tune_rounded,
                    onPressed: _showTools,
                  ),
                  _DockButton(
                    tooltip: 'Fosforlu kalem',
                    selected: widget.model.pen && widget.model.tool == InkTool.highlighter,
                    icon: InkTool.highlighter.icon,
                    onPressed: () => _select(InkTool.highlighter),
                  ),
                  _DockButton(
                    tooltip: 'Silgi',
                    selected: widget.model.pen && widget.model.tool == InkTool.eraser,
                    icon: InkTool.eraser.icon,
                    onPressed: () => _select(InkTool.eraser),
                  ),
                  if (widget.onFullscreen != null)
                    _DockButton(
                      tooltip: 'Tam ekran',
                      icon: Icons.fullscreen_rounded,
                      onPressed: widget.onFullscreen!,
                    ),
                ];
                final children = _left ? [main, if (_open) ...tools] : [if (_open) ...tools, main];
                return Row(mainAxisSize: MainAxisSize.min, children: children);
              },
            ),
          ),
        ),
      ),
    ],
  );
}

class _DockButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  const _DockButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(
          tooltip: tooltip,
          isSelected: selected,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
