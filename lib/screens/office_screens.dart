import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../widgets/common.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileTitle(widget.path), overflow: TextOverflow.ellipsis),
        actions: fileActions(context, widget.path),
      ),
      body: FutureBuilder<List<_Para>>(
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
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E6EC)),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
                  itemCount: paras.length,
                  itemBuilder: (_, i) {
                    final para = paras[i];
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
                                  fontWeight: (r.bold || isHead)
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  fontStyle:
                                      r.italic ? FontStyle.italic : FontStyle.normal,
                                  decoration: r.underline
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                              ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: _size(para.heading),
                          height: 1.5,
                          color: const Color(0xFF1B2430),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────── Sunum (.pptx) ─────────────────────────

class SlidesScreen extends StatefulWidget {
  final String path;
  const SlidesScreen({super.key, required this.path});

  @override
  State<SlidesScreen> createState() => _SlidesScreenState();
}

class _SlidesScreenState extends State<SlidesScreen> {
  late final Future<List<List<String>>> _future = _load();
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<List<List<String>>> _load() async {
    final arc = await _readZip(widget.path);
    final re = RegExp(r'^ppt/slides/slide(\d+)\.xml$');
    final files = arc.files.where((f) => re.hasMatch(f.name)).toList()
      ..sort((a, b) => int.parse(re.firstMatch(a.name)!.group(1)!)
          .compareTo(int.parse(re.firstMatch(b.name)!.group(1)!)));
    final slides = <List<String>>[];
    for (final f in files) {
      final doc = XmlDocument.parse(utf8.decode(f.content as List<int>));
      final lines = <String>[];
      for (final p in doc.findAllElements('a:p')) {
        final t = p.findAllElements('a:t').map((e) => e.innerText).join();
        if (t.trim().isNotEmpty) lines.add(t.trim());
      }
      slides.add(lines);
    }
    return slides;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileTitle(widget.path), overflow: TextOverflow.ellipsis),
        actions: fileActions(context, widget.path),
      ),
      body: FutureBuilder<List<List<String>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data!.isEmpty) {
            return _ErrorBox(
              'Bu sunum okunamadı. Sağ üstteki düğmeyle başka bir uygulamada açabilirsin.',
            );
          }
          final slides = snap.data!;
          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) {
                    final lines = slides[i];
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E6EC)),
                            ),
                            child: lines.isEmpty
                                ? const Center(child: Text('Bu slaytta metin yok'))
                                : ListView(
                                    children: [
                                      Text(
                                        lines.first,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      for (final l in lines.skip(1))
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Text('•  $l',
                                              style: const TextStyle(fontSize: 14)),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text('Slayt ${_page + 1} / ${slides.length}'),
              ),
            ],
          );
        },
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
