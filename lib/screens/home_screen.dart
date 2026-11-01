import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/doc_item.dart';
import '../services/device_index.dart';
import '../services/file_service.dart';
import '../services/recent_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'draw_screen.dart';
import 'note_screen.dart';
import 'viewer_router.dart';

enum _Sort { newest, name, size }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<DocFile> _recents = [];
  List<DocFile> _notes = [];
  List<DocFile> _device = [];

  DocKind? _filter;
  String _query = '';
  _Sort _sort = _Sort.newest;

  bool _loading = true;
  bool _scanning = false;
  bool _hasPerm = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ayarlardan izin verip dönünce otomatik tara.
    if (state == AppLifecycleState.resumed && !_hasPerm) _recheckPermission();
  }

  Future<void> _boot() async {
    await _loadLocal();
    final cached = await DeviceIndex.loadCached(); // anında
    final perm = await DeviceIndex.hasPermission();
    if (!mounted) return;
    setState(() {
      _device = cached;
      _hasPerm = perm;
      _loading = false;
    });
    if (perm) _refresh(); // arka planda güncelle
  }

  Future<void> _loadLocal() async {
    final paths = await RecentStore.load();
    final notes = await FileService.localFiles();
    if (!mounted) return;
    setState(() {
      _recents = paths.map(DocFile.fromPath).toList();
      _notes = notes;
    });
  }

  Future<void> _refresh() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final list = await DeviceIndex.refresh();
      if (mounted) setState(() => _device = list);
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _askPermission() async {
    final ok = await DeviceIndex.requestPermission();
    if (!mounted) return;
    setState(() => _hasPerm = ok);
    if (ok) _refresh();
  }

  Future<void> _recheckPermission() async {
    final ok = await DeviceIndex.hasPermission();
    if (!mounted || !ok) return;
    setState(() => _hasPerm = true);
    _refresh();
  }

  // ───────────── liste hesapları ─────────────

  List<DocFile> get _all {
    final seen = <String>{};
    final out = <DocFile>[];
    for (final d in [..._recents, ..._notes, ..._device]) {
      if (seen.add(d.path)) out.add(d);
    }
    return out;
  }

  List<DocFile> _filtered(List<DocFile> all) {
    final q = _query.toLowerCase();
    final list = all
        .where((d) =>
            (_filter == null || d.kind == _filter) &&
            (q.isEmpty || d.name.toLowerCase().contains(q)))
        .toList();
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case _Sort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _Sort.size:
        list.sort((a, b) => b.size.compareTo(a.size));
    }
    return list;
  }

  // ───────────── eylemler ─────────────

  Future<void> _open(String path) async {
    await openDocument(context, path);
    _loadLocal();
  }

  Future<void> _pick() async {
    final path = await FileService.pick();
    if (path != null && mounted) _open(path);
  }

  Future<void> _newNote() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NoteScreen()));
    _loadLocal();
  }

  Future<void> _newDrawing() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const DrawScreen()));
    _loadLocal();
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
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Dosya seç'),
              subtitle: const Text('Listede olmayan bir dosyayı aç'),
              onTap: () {
                Navigator.pop(ctx);
                _pick();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ───────────── arayüz ─────────────

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final all = _all;
    final list = _filtered(all);
    final browsing = _filter == null && _query.isEmpty;

    final counts = <DocKind, int>{};
    for (final d in all) {
      counts[d.kind] = (counts[d.kind] ?? 0) + 1;
    }

    final rows = <Object>[];
    if (browsing && _recents.isNotEmpty) {
      rows.add('Son açılanlar');
      rows.addAll(_recents.take(5));
    }
    final title = _filter != null
        ? '${kindInfo[_filter]!.label} (${list.length})'
        : browsing
            ? 'Tüm belgeler (${list.length})'
            : '${list.length} sonuç';
    rows.add(title);
    rows.addAll(list);

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
              padding: const EdgeInsets.fromLTRB(20, 16, 4, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Belgelerim',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                    ),
                  ),
                  PopupMenuButton<_Sort>(
                    tooltip: 'Sırala',
                    icon: const Icon(Icons.sort_rounded),
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: _Sort.newest, child: Text('En yeni')),
                      PopupMenuItem(value: _Sort.name, child: Text('Ada göre')),
                      PopupMenuItem(value: _Sort.size, child: Text('Boyuta göre')),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Tema',
                    onPressed: () => setThemeMode(
                      isDark ? ThemeMode.light : ThemeMode.dark,
                    ),
                    icon: Icon(isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded),
                  ),
                  IconButton(
                    tooltip: 'Yeniden tara',
                    onPressed: _scanning ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
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
                  fillColor: pal.card,
                  contentPadding: EdgeInsets.zero,
                  border: _border(),
                  enabledBorder: _border(),
                  focusedBorder: _border(),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _chip('Tümü', null, all.length),
                  for (final k in DocKind.values)
                    if (k != DocKind.other && (counts[k] ?? 0) > 0)
                      _chip(kindInfo[k]!.label, k, counts[k]!),
                ],
              ),
            ),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (!_hasPerm && Platform.isAndroid) _permissionCard(),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty && rows.length <= 1
                      ? _empty()
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              if (r is String) return _header(r);
                              return _tile(r as DocFile);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _border() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Pal.of(context).border),
      );

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Pal.of(context).muted,
          ),
        ),
      );

  Widget _permissionCard() => Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Pal.of(context).infoBox,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Telefondaki PDF, Word, Excel ve sunumları listelemek için dosya erişim izni ver.',
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _askPermission, child: const Text('İzin ver')),
          ],
        ),
      );

  Widget _chip(String label, DocKind? kind, int count) {
    final pal = Pal.of(context);
    final selected = _filter == kind;
    final color =
        kind == null ? Theme.of(context).colorScheme.primary : kindInfo[kind]!.color;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label  $count'),
        selected: selected,
        showCheckmark: false,
        selectedColor: color,
        labelStyle: TextStyle(
          color: selected ? Colors.white : pal.text,
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: pal.card,
        side: BorderSide(color: selected ? color : pal.border),
        onSelected: (_) => setState(() => _filter = kind),
      ),
    );
  }

  Widget _tile(DocFile d) {
    final pal = Pal.of(context);
    final info = kindInfo[d.kind]!;
    final isRecent = _recents.any((r) => r.path == d.path);
    final dir = p.basename(p.dirname(d.path));
    // "0" veya çok kısa/anlamsız klasör isimlerini gösterme
    final showDir = dir.length > 1 && dir != '0';
    return Material(
      color: pal.card,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.border),
        ),
        child: ListTile(
          onTap: () => _open(d.path),
          dense: true,
          contentPadding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
          minVerticalPadding: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: info.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(info.icon, color: info.color, size: 20),
          ),
          title: Text(
            d.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            '${d.ext}  ·  ${formatSize(d.size)}  ·  ${formatDate(d.modified)}'
            '${showDir ? '\n$dir' : ''}',
            maxLines: showDir ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: pal.muted),
          ),
          isThreeLine: showDir,
          trailing: isRecent
              ? PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'remove') {
                      await RecentStore.remove(d.path);
                      _loadLocal();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Son açılanlardan kaldır'),
                    ),
                  ],
                )
              : const Icon(Icons.chevron_right_rounded, size: 20),
        ),
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
              _query.isNotEmpty || _filter != null
                  ? 'Eşleşen belge yok'
                  : _scanning
                      ? 'Belgeler taranıyor…'
                      : 'Henüz belge yok',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'İlk tarama biraz sürebilir, sonraki açılışlar anında olur.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
