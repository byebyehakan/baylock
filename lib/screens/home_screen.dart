import 'package:flutter/material.dart';

import '../models/doc_item.dart';
import '../services/file_service.dart';
import '../services/recent_store.dart';
import '../widgets/common.dart';
import 'draw_screen.dart';
import 'note_screen.dart';
import 'viewer_router.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DocFile> _recents = [];
  List<DocFile> _local = [];
  List<DocFile> _device = [];
  DocKind? _filter;
  String _query = '';
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paths = await RecentStore.load();
    final local = await FileService.localFiles();
    if (!mounted) return;
    setState(() {
      _recents = paths.map(DocFile.fromPath).toList();
      _local = local;
      _loading = false;
    });
  }

  List<DocFile> get _visible {
    final seen = <String>{};
    final all = <DocFile>[];
    for (final d in [..._recents, ..._local, ..._device]) {
      if (seen.add(d.path)) all.add(d);
    }
    final q = _query.toLowerCase();
    return all
        .where((d) =>
            (_filter == null || d.kind == _filter) &&
            (q.isEmpty || d.name.toLowerCase().contains(q)))
        .toList();
  }

  Future<void> _open(String path) async {
    await openDocument(context, path);
    _load();
  }

  Future<void> _pick() async {
    final path = await FileService.pick();
    if (path != null && mounted) _open(path);
  }

  Future<void> _newNote() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NoteScreen()));
    _load();
  }

  Future<void> _newDrawing() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const DrawScreen()));
    _load();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final found = await FileService.deviceScan();
    if (!mounted) return;
    setState(() {
      _device = found;
      _scanning = false;
    });
    toast(context, '${found.length} belge bulundu');
  }

  void _showNewSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Dosya aç'),
              subtitle: const Text('PDF, Word, Excel, sunum, metin, görsel'),
              onTap: () {
                Navigator.pop(ctx);
                _pick();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Yeni not yaz'),
              onTap: () {
                Navigator.pop(ctx);
                _newNote();
              },
            ),
            ListTile(
              leading: const Icon(Icons.draw_rounded),
              title: const Text('Yeni çizim'),
              onTap: () {
                Navigator.pop(ctx);
                _newDrawing();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Belgelerim',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                    ),
                  ),
                  _scanning
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Cihazda belge ara',
                          onPressed: _scan,
                          icon: const Icon(Icons.travel_explore_rounded),
                        ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Belge ara',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E6EC)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E6EC)),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _chip('Tümü', null),
                  for (final k in DocKind.values.where((k) => k != DocKind.other))
                    _chip(kindInfo[k]!.label, k),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? _empty()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _tile(items[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, DocKind? kind) {
    final selected = _filter == kind;
    final color = kind == null ? Theme.of(context).colorScheme.primary : kindInfo[kind]!.color;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: color,
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF14202F),
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? color : const Color(0xFFE2E6EC)),
        onSelected: (_) => setState(() => _filter = kind),
      ),
    );
  }

  Widget _tile(DocFile d) {
    final info = kindInfo[d.kind]!;
    final isRecent = _recents.any((r) => r.path == d.path);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E6EC)),
      ),
      child: ListTile(
        onTap: () => _open(d.path),
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: info.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(info.icon, color: info.color),
        ),
        title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${d.ext}  ·  ${formatSize(d.size)}  ·  ${formatDate(d.modified)}'),
        trailing: isRecent
            ? PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'remove') {
                    await RecentStore.remove(d.path);
                    _load();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('Son açılanlardan kaldır')),
                ],
              )
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_rounded, size: 56, color: Color(0xFF9AA6B5)),
            const SizedBox(height: 12),
            Text(
              _query.isNotEmpty || _filter != null ? 'Eşleşen belge yok' : 'Henüz belge yok',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Cihazından bir dosya seç, yeni bir not yaz ya da çizim yap.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Dosya aç'),
            ),
          ],
        ),
      ),
    );
  }
}
