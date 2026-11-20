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
  static const _accentColors = <String, Color>{
    'Lacivert': Color(0xFF1E3A5F),
    'Mavi': Color(0xFF2563EB),
    'Turkuaz': Color(0xFF0F766E),
    'Yeşil': Color(0xFF388E3C),
    'Turuncu': Color(0xFFEA580C),
    'Kırmızı': Color(0xFFC62828),
    'Mor': Color(0xFF7E57C2),
    'Gri': Color(0xFF546E7A),
  };

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
    if (mounted)
      setState(() {
        _cacheBytes = cache;
        _annotBytes = annot;
      });
  }

  Future<void> _clearCache() async {
    try {
      final tmp = await getTemporaryDirectory();
      for (final e in tmp.listSync()) {
        try {
          e.deleteSync(recursive: true);
        } catch (_) {}
      }
      if (mounted) {
        toast(context, 'Önbellek temizlendi');
        _calcSizes();
      }
    } catch (_) {
      if (mounted) toast(context, 'Temizlenemedi');
    }
  }

  Future<void> _clearAnnotations() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm çizimler silinsin mi?'),
        content: const Text(
          'PDF, Word ve diğer belgelere yapılan tüm çizimler kalıcı olarak silinir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
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
      if (mounted) {
        toast(context, 'Tüm çizimler silindi');
        _calcSizes();
      }
    } catch (_) {
      if (mounted) toast(context, 'Silinemedi');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final mode = themeMode.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Görünümünü kişiselleştir, depolamanı yönet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _section('Görünüm'),
              _card(pal, [
                _settingTile(
                  icon: Icons.brightness_6_rounded,
                  title: 'Tema',
                  subtitle: switch (mode) {
                    ThemeMode.dark => 'Karanlık',
                    ThemeMode.light => 'Aydınlık',
                    ThemeMode.system => 'Sistem',
                  },
                  onTap: () => _showThemePicker(context),
                ),
                _divider(pal),
                ValueListenableBuilder<Color>(
                  valueListenable: accentColor,
                  builder: (context, color, _) => _settingTile(
                    icon: Icons.palette_outlined,
                    title: 'Renk paleti',
                    subtitle: _accentColors.entries
                        .firstWhere(
                          (entry) => entry.value.toARGB32() == color.toARGB32(),
                          orElse: () => MapEntry('Özel', color),
                        )
                        .key,
                    onTap: _showAccentPicker,
                  ),
                ),
              ]),
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
                  subtitle: _annotBytes > 0
                      ? '${formatSize(_annotBytes)} yer kaplıyor'
                      : 'Çizim yok',
                  danger: _annotBytes > 0,
                  onTap: _annotBytes > 0 ? _clearAnnotations : null,
                ),
              ]),
            ],
          ),
        ),
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tema',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            for (final entry in {
              ThemeMode.system: ('Sistem', Icons.brightness_auto_rounded),
              ThemeMode.light: ('Aydınlık', Icons.light_mode_rounded),
              ThemeMode.dark: ('Karanlık', Icons.dark_mode_rounded),
            }.entries)
              ListTile(
                leading: Icon(entry.value.$2),
                title: Text(entry.value.$1),
                trailing: themeMode.value == entry.key
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () async {
                  try {
                    await setThemeMode(entry.key);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  } catch (error) {
                    if (ctx.mounted) {
                      toast(ctx, 'Tema kaydedilemedi: $error');
                    }
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAccentPicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Pal.of(context).card,
      builder: (ctx) => SafeArea(
        child: ValueListenableBuilder<Color>(
          valueListenable: accentColor,
          builder: (context, selectedColor, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Renk paleti',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final entry in _accentColors.entries)
                      Tooltip(
                        message: entry.key,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () async {
                            try {
                              await setAccentColor(entry.value);
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (error) {
                              if (ctx.mounted) {
                                toast(ctx, 'Renk kaydedilemedi: $error');
                              }
                            }
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: entry.value,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    selectedColor.toARGB32() ==
                                        entry.value.toARGB32()
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child:
                                selectedColor.toARGB32() ==
                                    entry.value.toARGB32()
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 9),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );

  Widget _card(Pal pal, List<Widget> children) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: pal.card,
      borderRadius: BorderRadius.circular(18),
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
    final theme = Theme.of(context);
    final color = danger
        ? theme.colorScheme.error
        : onTap != null
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return ListTile(
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, size: 21, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: danger ? color : null,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: onTap != null
          ? Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : null,
      onTap: onTap,
    );
  }
}
