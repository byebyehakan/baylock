import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../ink/ink_session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page_notes_button.dart';
import '../widgets/quick_scroll_rail.dart';
import '../widgets/share_with_notes_button.dart';

Future<Archive> _readZip(String path) async {
  final bytes = await File(path).readAsBytes();
  return ZipDecoder().decodeBytes(bytes);
}

String _xmlOf(Archive arc, String name) {
  final f = arc.findFile(name);
  if (f == null) throw Exception('$name bulunamadı');
  return utf8.decode(f.content as List<int>);
}

// ───────────────────────── Word (.docx) ─────────────────────────

class _Run {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  const _Run(this.text, this.bold, this.italic, this.underline);
}

class _Para {
  final List<_Run> runs;
  final int heading; // 0 = başlık, 1-3 = alt başlıklar, -1 = normal
  const _Para(this.runs, this.heading);
}

class WordScreen extends StatefulWidget {
  final String path;
  const WordScreen({super.key, required this.path});

  @override
  State<WordScreen> createState() => _WordScreenState();
}

class _WordScreenState extends State<WordScreen> {
  late final Future<List<_Para>> _future = _load();
  final _scrollController = ScrollController();

  Future<List<_Para>> _load() async {
    final arc = await _readZip(widget.path);
    final doc = XmlDocument.parse(_xmlOf(arc, 'word/document.xml'));
    final paras = <_Para>[];
    for (final p in doc.findAllElements('w:p')) {
      var heading = -1;
      for (final s in p.findAllElements('w:pStyle')) {
        final v = (s.getAttribute('w:val') ?? '').toLowerCase();
        if (v == 'title') {
          heading = 0;
        } else {
          final m = RegExp(r'heading\s*(\d)').firstMatch(v);
          if (m != null) heading = int.parse(m.group(1)!).clamp(1, 3);
        }
        break;
      }
      final runs = <_Run>[];
      for (final r in p.findAllElements('w:r')) {
        final text = r.findAllElements('w:t').map((e) => e.innerText).join();
        if (text.isEmpty) continue;
        runs.add(_Run(
          text,
          r.findAllElements('w:b').isNotEmpty,
          r.findAllElements('w:i').isNotEmpty,
          r.findAllElements('w:u').isNotEmpty,
        ));
      }
      paras.add(_Para(runs, heading));
    }
    return paras;
  }

  double _size(int h) => switch (h) { 0 => 28, 1 => 24, 2 => 20, 3 => 18, _ => 16 };

  late final InkSession _ink = InkSession(widget.path);

  @override
  void dispose() {
    _scrollController.dispose();
    _ink.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Widget _paraWidget(_Para para, Pal pal) {
    if (para.runs.isEmpty) return const SizedBox(height: 12);
    final isHead = para.heading >= 0;
    return Padding(
      padding: EdgeInsets.only(top: isHead ? 14 : 0, bottom: 8),
      child: SelectableText.rich(
        TextSpan(
          children: [
            for (final r in para.runs)
              TextSpan(
                text: r.text,
                style: TextStyle(
                  fontWeight: (r.bold || isHead) ? FontWeight.w700 : FontWeight.w400,
                  fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
                  decoration:
                      r.underline ? TextDecoration.underline : TextDecoration.none,
                ),
              ),
          ],
        ),
        style: TextStyle(
          fontSize: _size(para.heading),
          height: 1.5,
          color: pal.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    _ink.adaptColor(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(fileTitle(widget.path), overflow: TextOverflow.ellipsis),
        actions: [
          _ink.penButton(context, _refresh),
          ShareWithNotesButton(documentPath: widget.path),
          PageNotesButton(
            documentPath: widget.path,
            pageKey: () => 'word-1',
            pageLabel: () => 'Belge',
          ),
          ...fileActions(context, widget.path),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<_Para>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _ErrorBox(
                    'Bu Word dosyası okunamadı. Sağ üstteki düğmeyle başka bir uygulamada açabilirsin.',
                  );
                }
                final paras = snap.data!;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: pal.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: pal.border),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _ink.watch(
                              () => SingleChildScrollView(
                                controller: _scrollController,
                                physics: _ink.physics,
                                child: _ink.overlay(
                                  page: 1,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      22,
                                      24,
                                      22,
                                      40,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final para in paras)
                                          _paraWidget(para, pal),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: QuickScrollRail(
                                controller: _scrollController,
                              ),
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
          if (_ink.pen) _ink.toolbar(context, _refresh),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
}
