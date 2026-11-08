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
import 'settings_screen.dart';
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
  List<DocFile>? _allCache;
  List<DocFile>? _filteredCache;
  Map<DocKind, int>? _kindCountsCache;
  String? _filteredQuery;
  DocKind? _filteredKind;
  _Sort? _filteredSort;

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
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && !_hasPerm) _recheckPerm();
  }

  Future<void> _boot() async {
    await _loadLocal();
    final cached = await DeviceIndex.loadCached();
    final perm = await DeviceIndex.hasPermission();
    if (!mounted) return;
    _invalidateFileCaches();
    setState(() {
      _device = cached;
      _hasPerm = perm;
      _loading = false;
    });
    if (perm) _refresh();
  }

  Future<void> _loadLocal() async {
    final paths = await RecentStore.load();
    final notes = await FileService.localFiles();
    final recents = await Future.wait(paths.map(DocFile.fromPathAsync));
    if (!mounted) return;
    _invalidateFileCaches();
    setState(() {
      _recents = recents;
      _notes = notes;
    });
  }

  Future<void> _refresh() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final list = await DeviceIndex.refresh();
      if (mounted) {
        _invalidateFileCaches();
        setState(() => _device = list);
      }
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _askPermission() async {
    final ok = await DeviceIndex.requestPermission();
    if (!mounted) return;
    setState(() => _hasPerm = ok);
    if (ok) _refresh();
  }

  Future<void> _recheckPerm() async {
    final ok = await DeviceIndex.hasPermission();
    if (!mounted || !ok) return;
    setState(() => _hasPerm = true);
    _refresh();
  }

  void _invalidateFileCaches() {
    _allCache = null;
    _filteredCache = null;
    _kindCountsCache = null;
  }

  void _invalidateFilteredCache() {
    _filteredCache = null;
  }

  List<DocFile> get _all {
    final cached = _allCache;
    if (cached != null) return cached;
    final seen = <String>{};
    final out = <DocFile>[];
    for (final d in [..._recents, ..._notes, ..._device]) {
      if (seen.add(d.path)) out.add(d);
    }
    return _allCache = out;
  }

  List<DocFile> _filtered(List<DocFile> all) {
    final cached = _filteredCache;
    if (cached != null &&
        _filteredQuery == _query &&
        _filteredKind == _filter &&
        _filteredSort == _sort) {
      return cached;
    }
    final q = _query.toLowerCase();
    final list = all
        .where(
          (d) =>
              (_filter == null || d.kind == _filter) &&
              (q.isEmpty || d.name.toLowerCase().contains(q)),
        )
        .toList();
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case _Sort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _Sort.size:
        list.sort((a, b) => b.size.compareTo(a.size));
    }
    _filteredQuery = _query;
    _filteredKind = _filter;
    _filteredSort = _sort;
    return _filteredCache = list;
  }

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
      backgroundColor: Pal.of(context).card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTile(
              ctx,
              Icons.edit_note_rounded,
              'Yeni not',
              'Metin belgesi oluştur',
              _newNote,
            ),
            _sheetTile(
              ctx,
              Icons.draw_rounded,
              'Yeni çizim',
              'Boş sayfa üzerinde çiz',
              _newDrawing,
            ),
            _sheetTile(
              ctx,
              Icons.folder_open_rounded,
              'Dosya seç',
              'Cihazdan belge aç',
              _pick,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile(
    BuildContext ctx,
    IconData icon,
    String title,
    String sub,
    VoidCallback cb,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub),
      onTap: () {
        Navigator.pop(ctx);
        cb();
      },
    );
  }

  // ── rename / delete ──────────────────────────────────────────
  Future<void> _rename(DocFile d) async {
    final ctrl = TextEditingController(
      text: p.basenameWithoutExtension(d.path),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeniden adlandır'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Dosya adı'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final ext = p.extension(d.path);
    final newPath = p.join(p.dirname(d.path), '$result$ext');
    try {
      await File(d.path).rename(newPath);
      await RecentStore.remove(d.path);
      await RecentStore.add(newPath);
      _loadLocal();
      if (mounted) toast(context, 'Yeniden adlandırıldı');
    } catch (e) {
      if (mounted) toast(context, 'Hata: $e');
    }
  }

  Future<void> _delete(DocFile d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dosyayı sil'),
        content: Text('"${d.name}" silinsin mi? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await File(d.path).delete();
      await RecentStore.remove(d.path);
      _loadLocal();
      if (mounted) toast(context, 'Silindi');
    } catch (e) {
      if (mounted) toast(context, 'Silinemedi: $e');
    }
  }

  void _showFileMenu(DocFile d) {
    final isRecent = _recents.any((r) => r.path == d.path);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Pal.of(context).card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Icon(
                    kindInfo[d.kind]!.icon,
                    color: kindInfo[d.kind]!.color,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Aç'),
              onTap: () {
                Navigator.pop(ctx);
                _open(d.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Yeniden adlandır'),
              onTap: () {
                Navigator.pop(ctx);
                _rename(d);
              },
            ),
            if (isRecent)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Son açılanlardan kaldır'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await RecentStore.remove(d.path);
                  _loadLocal();
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Bilgi'),
              onTap: () {
                Navigator.pop(ctx);
                _showInfo(d);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
              ),
              title: const Text('Sil', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(d);
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _showInfo(DocFile d) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final pal = Pal.of(ctx);
        return AlertDialog(
          title: Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Tür', d.ext, pal),
              _infoRow('Boyut', formatSize(d.size), pal),
              _infoRow('Değiştirilme', formatDate(d.modified), pal),
              _infoRow('Konum', d.path, pal),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(String label, String value, Pal pal) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: pal.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    ),
  );

  // ── build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final all = _all;
    final list = _filtered(all);

    final counts = _kindCountsCache ??= () {
      final result = <DocKind, int>{};
      for (final d in all) {
        result[d.kind] = (result[d.kind] ?? 0) + 1;
      }
      return result;
    }();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewSheet,
        tooltip: 'Yeni',
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── top bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Belgelerim',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Belgelerin ve notların tek yerde',
                          style: TextStyle(fontSize: 12, color: pal.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sırala',
                    onPressed: _showSortSheet,
                    icon: const Icon(Icons.sort_rounded),
                  ),
                  IconButton(
                    tooltip: 'Ayarlar',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
            // ── search ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                onChanged: (v) {
                  _invalidateFilteredCache();
                  setState(() => _query = v);
                },
                decoration: InputDecoration(
                  hintText: 'Belge ara…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: pal.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: _inputBorder(),
                  enabledBorder: _inputBorder(),
                  focusedBorder: _inputBorder(focused: true),
                ),
              ),
            ),
            // ── filter chips ──
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
            if (!_hasPerm && Platform.isAndroid) _permBanner(),
            const SizedBox(height: 8),
            // ── list ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (_query.isEmpty &&
                              _filter == null &&
                              _recents.isNotEmpty) ...[
                            _sectionHeader('Son açılanlar'),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => _tile(_recents[i < 3 ? i : 2]),
                                  childCount: _recents.length.clamp(0, 3),
                                ),
                              ),
                            ),
                          ],
                          _sectionHeader(
                            _filter != null
                                ? '${kindInfo[_filter]!.label} · ${list.length}'
                                : _query.isNotEmpty
                                ? '${list.length} sonuç'
                                : 'Tüm belgeler · ${list.length}',
                          ),
                          list.isEmpty
                              ? SliverFillRemaining(child: _empty())
                              : SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    100,
                                  ),
                                  sliver: SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (_, i) => _tile(list[i]),
                                      childCount: list.length,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Pal.of(context).card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sırala',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            for (final entry in {
              _Sort.newest: ('En yeni', Icons.access_time_rounded),
              _Sort.name: ('Ada göre', Icons.sort_by_alpha_rounded),
              _Sort.size: ('Boyuta göre', Icons.data_usage_rounded),
            }.entries)
              ListTile(
                leading: Icon(entry.value.$2),
                title: Text(entry.value.$1),
                trailing: _sort == entry.key
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  _invalidateFilteredCache();
                  setState(() => _sort = entry.key);
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _inputBorder({bool focused = false}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: focused
          ? Theme.of(context).colorScheme.primary
          : Pal.of(context).border,
      width: focused ? 1.5 : 1,
    ),
  );

  SliverToBoxAdapter _sectionHeader(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Pal.of(context).muted,
          letterSpacing: 0.3,
        ),
      ),
    ),
  );

  Widget _chip(String label, DocKind? kind, int count) {
    final pal = Pal.of(context);
    final selected = _filter == kind;
    final color = kind == null
        ? Theme.of(context).colorScheme.primary
        : kindInfo[kind]!.color;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(
          '$label  $count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : pal.text,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        selectedColor: color,
        backgroundColor: pal.card,
        side: BorderSide(color: selected ? color : pal.border),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          _invalidateFilteredCache();
          setState(() => _filter = selected ? null : kind);
        },
      ),
    );
  }

  Widget _tile(DocFile d) {
    final pal = Pal.of(context);
    final info = kindInfo[d.kind]!;
    final dir = p.basename(p.dirname(d.path));
    final showDir = dir.length > 2 && dir != '0';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(d.path),
        onLongPress: () => _showFileMenu(d),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: pal.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pal.border),
          ),
          child: Row(
            children: [
              // ikon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: info.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(info.icon, color: info.color, size: 20),
              ),
              const SizedBox(width: 12),
              // metin
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.ext}  ·  ${formatSize(d.size)}  ·  ${formatDate(d.modified)}'
                      '${showDir ? "  ·  $dir" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: pal.muted),
                    ),
                  ],
                ),
              ),
              // aksiyon
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _showFileMenu(d),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Pal.of(context).infoBox,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.folder_outlined, size: 18),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Cihazdaki belgeleri görmek için izin ver.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        TextButton(onPressed: _askPermission, child: const Text('İzin ver')),
      ],
    ),
  );

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 52,
            color: Pal.of(context).muted,
          ),
          const SizedBox(height: 14),
          Text(
            _query.isNotEmpty || _filter != null
                ? 'Eşleşen belge yok'
                : _scanning
                ? 'Taranıyor…'
                : 'Henüz belge yok',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'İlk tarama biraz sürebilir.',
            style: TextStyle(fontSize: 13, color: Pal.of(context).muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
