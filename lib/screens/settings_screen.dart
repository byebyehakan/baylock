import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _cacheBytes = 0;
  int _annotBytes = 0;

  @override
  void initState() {
    super.initState();
    _calcSizes();
  }

  Future<void> _calcSizes() async {
    int cache = 0, annot = 0;
    try {
      final tmp = await getTemporaryDirectory();
      for (final e in tmp.listSync(recursive: true)) {
        if (e is File) cache += e.statSync().size;
      }
    } catch (_) {}
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/annotations');
      if (dir.existsSync()) {
        for (final e in dir.listSync()) {
          if (e is File) annot += e.statSync().size;
        }
      }
    } catch (_) {}
    if (mounted) setState(() { _cacheBytes = cache; _annotBytes = annot; });
  }

  Future<void> _clearCache() async {
    try {
      final tmp = await getTemporaryDirectory();
      for (final e in tmp.listSync()) {
        try { e.deleteSync(recursive: true); } catch (_) {}
      }
      if (mounted) { toast(context, 'Önbellek temizlendi'); _calcSizes(); }
    } catch (_) {
      if (mounted) toast(context, 'Temizlenemedi');
    }
  }

  Future<void> _clearAnnotations() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm çizimler silinsin mi?'),
        content: const Text('PDF, Word ve diğer belgelere yapılan tüm çizimler kalıcı olarak silinir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
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
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/annotations');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      if (mounted) { toast(context, 'Tüm çizimler silindi'); _calcSizes(); }
    } catch (_) {
      if (mounted) toast(context, 'Silinemedi');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal    = Pal.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode   = themeMode.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [

          // ── Görünüm ──────────────────────────────────────
          _section('Görünüm'),
          _card(pal, [
            _settingTile(
              icon: Icons.brightness_6_rounded,
              title: 'Tema',
              subtitle: switch (mode) {
                ThemeMode.dark   => 'Karanlık',
                ThemeMode.light  => 'Aydınlık',
                ThemeMode.system => 'Sistem',
              },
              onTap: () => _showThemePicker(context),
            ),
          ]),

          // ── Depolama ─────────────────────────────────────
          _section('Depolama'),
          _card(pal, [
            _settingTile(
              icon: Icons.cleaning_services_rounded,
              title: 'Önbelleği temizle',
              subtitle: _cacheBytes > 0 ? formatSize(_cacheBytes) : 'Boş',
              onTap: _cacheBytes > 0 ? _clearCache : null,
            ),
            _divider(pal),
            _settingTile(
              icon: Icons.draw_rounded,
              title: 'Tüm çizimleri sil',
              subtitle: _annotBytes > 0 ? '${formatSize(_annotBytes)} yer kaplıyor' : 'Çizim yok',
              danger: _annotBytes > 0,
              onTap: _annotBytes > 0 ? _clearAnnotations : null,
            ),
          ]),

          // ── Hakkında ─────────────────────────────────────
          _section('Hakkında'),
          _card(pal, [
            _settingTile(
              icon: Icons.info_outline_rounded,
              title: 'Baylock',
              subtitle: 'Sürüm 0.1.0',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Baylock',
                applicationVersion: '0.1.0',
                applicationLegalese: '© 2026',
                children: const [
                  SizedBox(height: 12),
                  Text('PDF, Word, Excel ve sunumları açan, '
                       'her belgeye çizim yapmana izin veren belge yöneticisi.'),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showThemePicker(BuildContext context) {
    final pal = Pal.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: pal.card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Align(alignment: Alignment.centerLeft,
                child: Text('Tema', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ),
            for (final entry in {
              ThemeMode.system : ('Sistem',    Icons.brightness_auto_rounded),
              ThemeMode.light  : ('Aydınlık',  Icons.light_mode_rounded),
              ThemeMode.dark   : ('Karanlık',  Icons.dark_mode_rounded),
            }.entries)
              ListTile(
                leading: Icon(entry.value.$2),
                title: Text(entry.value.$1),
                trailing: themeMode.value == entry.key ? const Icon(Icons.check_rounded) : null,
                onTap: () { setThemeMode(entry.key); Navigator.pop(ctx); setState(() {}); },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
    child: Text(title.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: Pal.of(context).muted, letterSpacing: 0.8)),
  );

  Widget _card(Pal pal, List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: pal.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: pal.border),
    ),
    child: Column(children: children),
  );

  Widget _divider(Pal pal) => Divider(height: 1, indent: 54, color: pal.border);

  Widget _settingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? Colors.red : null;
    return ListTile(
      leading: Icon(icon, size: 22, color: color),
      title: Text(title, style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: color)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12))
          : null,
      trailing: onTap != null
          ? const Icon(Icons.chevron_right_rounded, size: 18)
          : null,
      onTap: onTap,
    );
  }
}
