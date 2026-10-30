import 'dart:io';
import 'dart:math';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../widgets/common.dart';

class SheetScreen extends StatefulWidget {
  final String path;
  const SheetScreen({super.key, required this.path});

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  static const _cw = 120.0;
  static const _rh = 40.0;

  Excel? _xl;
  final Map<String, List<List<String>>> _sheets = {};
  String? _current;
  bool _loading = true;
  bool _dirty = false;
  String? _error;

  bool get _isCsv => p.extension(widget.path).toLowerCase() == '.csv';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_isCsv) {
        final text = await File(widget.path).readAsString();
        _sheets['CSV'] = _parseCsv(text);
      } else {
        final xl = Excel.decodeBytes(await File(widget.path).readAsBytes());
        _xl = xl;
        for (final name in xl.tables.keys) {
          final t = xl.tables[name]!;
          _sheets[name] = t.rows
              .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
              .toList();
        }
      }
      _current = _sheets.keys.isEmpty ? null : _sheets.keys.first;
    } catch (e) {
      _error = 'Bu tablo okunamadı. Sağ üstteki düğmeyle başka bir uygulamada açabilirsin.';
    }
    if (mounted) setState(() => _loading = false);
  }

  List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',' || ch == ';') {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if (ch == '\n') {
        row.add(cell.toString());
        rows.add(row);
        row = <String>[];
        cell = StringBuffer();
      } else if (ch != '\r') {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  String _csvEscape(String s) =>
      (s.contains(',') || s.contains('"') || s.contains('\n'))
          ? '"${s.replaceAll('"', '""')}"'
          : s;

  String _colName(int i) {
    var s = '';
    var n = i + 1;
    while (n > 0) {
      final m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  Future<void> _save() async {
    try {
      if (_isCsv) {
        final rows = _sheets['CSV']!;
        final txt = rows.map((r) => r.map(_csvEscape).join(',')).join('\n');
        await File(widget.path).writeAsString(txt);
      } else {
        final bytes = _xl!.save();
        if (bytes != null) await File(widget.path).writeAsBytes(bytes);
      }
      if (!mounted) return;
      setState(() => _dirty = false);
      toast(context, 'Kaydedildi');
    } catch (_) {
      if (mounted) toast(context, 'Kaydedilemedi');
    }
  }

  Future<void> _editCell(int r, int c) async {
    final rows = _sheets[_current]!;
    final old = c < rows[r].length ? rows[r][c] : '';
    final ctrl = TextEditingController(text: old);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_colName(c)}${r + 1} hücresi'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    if (result == null || result == old) return;

    setState(() {
      while (rows[r].length <= c) {
        rows[r].add('');
      }
      rows[r][c] = result;
      _dirty = true;
    });
    if (_xl != null) {
      final number = double.tryParse(result.replaceAll(',', '.'));
      _xl!.tables[_current]!.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
        number != null ? DoubleCellValue(number) : TextCellValue(result),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileTitle(widget.path), overflow: TextOverflow.ellipsis),
        actions: [
          if (_dirty)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Kaydet'),
            ),
          ...fileActions(context, widget.path),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _current == null
                  ? const Center(child: Text('Tablo boş'))
                  : Column(
                      children: [
                        Expanded(child: _grid()),
                        if (_sheets.length > 1) _tabs(),
                      ],
                    ),
    );
  }

  Widget _tabs() {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final name in _sheets.keys)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(name),
                selected: name == _current,
                onSelected: (_) => setState(() => _current = name),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid() {
    final rows = _sheets[_current]!;
    final cols = max(1, rows.fold<int>(0, (m, r) => max(m, r.length)));
    const border = BorderSide(color: Color(0xFFE2E6EC));

    Widget cell(String text, {double w = _cw, bool head = false, VoidCallback? onTap}) {
      return InkWell(
        onTap: onTap,
        child: Container(
          width: w,
          height: _rh,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: head ? const Color(0xFFEEF1F5) : Colors.white,
            border: const Border(right: border, bottom: border),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: head ? FontWeight.w600 : FontWeight.w400,
              color: head ? const Color(0xFF5A6B7F) : const Color(0xFF1B2430),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 48 + cols * _cw,
        child: ListView.builder(
          itemCount: rows.length + 1,
          itemExtent: _rh,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Row(children: [
                cell('', w: 48, head: true),
                for (var c = 0; c < cols; c++) cell(_colName(c), head: true),
              ]);
            }
            final r = i - 1;
            return Row(children: [
              cell('${r + 1}', w: 48, head: true),
              for (var c = 0; c < cols; c++)
                cell(
                  c < rows[r].length ? rows[r][c] : '',
                  onTap: () => _editCell(r, c),
                ),
            ]);
          },
        ),
      ),
    );
  }
}