import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import 'package:uuid/uuid.dart';
import '../../../core/database/db_helper.dart';
import '../../../core/theme/app_spacing.dart';
import '../../analytics/analytics_provider.dart';
import '../dashboard_screen.dart';

class OeeExcelImportDialog extends ConsumerStatefulWidget {
  const OeeExcelImportDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const OeeExcelImportDialog(),
    );
  }

  @override
  ConsumerState<OeeExcelImportDialog> createState() => _OeeExcelImportDialogState();
}

class _OeeExcelImportDialogState extends ConsumerState<OeeExcelImportDialog> {
  File? _selectedFile;
  String? _fileName;
  List<String> _headers = [];
  List<List<dynamic>> _rawRows = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  int _colMachine = -1;
  int _colDate = -1;
  int _colHours = -1;
  int _colTarget = -1;
  int _colActual = -1;
  int _colGood = -1;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        setState(() {
          _selectedFile = file;
          _fileName = result.files.single.name;
          _isLoading = true;
          _errorMessage = null;
        });

        await _parseFile(file);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'ไม่สามารถอ่านไฟล์ได้: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _parseFile(File file) async {
    try {
      final ext = file.path.split('.').last.toLowerCase();
      List<String> headers = [];
      List<List<dynamic>> rows = [];

      if (ext == 'csv') {
        final content = await file.readAsString();
        final lines = const LineSplitter().convert(content);
        if (lines.isNotEmpty) {
          final firstLine = lines.first;
          final delimiter = firstLine.contains('\t') ? '\t' : (firstLine.contains(';') ? ';' : ',');
          headers = firstLine.split(delimiter).map((e) => e.replaceAll('"', '').trim()).toList();
          for (var i = 1; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.isNotEmpty) {
              final cells = line.split(delimiter).map((e) => e.replaceAll('"', '').trim()).toList();
              rows.add(cells);
            }
          }
        }
      } else {
        final bytes = await file.readAsBytes();
        final excel = xl.Excel.decodeBytes(bytes);
        final firstSheetName = excel.tables.keys.first;
        final sheet = excel.tables[firstSheetName];

        if (sheet != null && sheet.rows.isNotEmpty) {
          headers = sheet.rows.first.map((cell) => cell?.value?.toString().trim() ?? '').toList();
          for (var i = 1; i < sheet.rows.length; i++) {
            final row = sheet.rows[i].map((cell) => cell?.value?.toString() ?? '').toList();
            if (row.any((element) => element.isNotEmpty)) {
              rows.add(row);
            }
          }
        }
      }

      if (headers.isEmpty) {
        throw Exception('ไม่พบหัวคอลัมน์ในไฟล์');
      }

      _autoDetectColumns(headers);

      setState(() {
        _headers = headers;
        _rawRows = rows;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดในการวิเคราะห์ไฟล์: ';
        _isLoading = false;
      });
    }
  }

  void _autoDetectColumns(List<String> headers) {
    _colMachine = _findColumnIndex(headers, [r'machine', r'mc', r'm/c', r'เครื่อง', r'รหัสเครื่อง', r'line']);
    _colDate = _findColumnIndex(headers, [r'date', r'วันที่', r'วัน', r'time']);
    _colHours = _findColumnIndex(headers, [r'hour', r'hrs', r'hr', r'ชม', r'ชั่วโมง', r'uptime', r'run']);
    _colTarget = _findColumnIndex(headers, [r'target', r'plan', r'เป้า', r'เป้าหมาย', r'ยอดเป้า']);
    _colActual = _findColumnIndex(headers, [r'actual', r'output', r'ผลิตได้', r'ยอดจริง', r'ยอดผลิต']);
    _colGood = _findColumnIndex(headers, [r'good', r'ok', r'ของดี', r'งานดี', r'pass']);
  }

  int _findColumnIndex(List<String> headers, List<String> patterns) {
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase();
      for (final p in patterns) {
        if (RegExp(p, caseSensitive: false).hasMatch(h)) {
          return i;
        }
      }
    }
    return -1;
  }

  double _parseDouble(dynamic val, {double fallback = 0.0}) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    final clean = val.toString().replaceAll(',', '').trim();
    return double.tryParse(clean) ?? fallback;
  }

  DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    final s = val.toString().trim();
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return parsed;

    if (s.contains('/')) {
      final parts = s.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]) ?? 1;
        final m = int.tryParse(parts[1]) ?? 1;
        var y = int.tryParse(parts[2]) ?? DateTime.now().year;
        if (y > 2500) y -= 543;
        return DateTime(y, m, d);
      }
    }
    return DateTime.now();
  }

  Future<void> _saveData() async {
    if (_colMachine == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกคอลัมน์รหัสเครื่องจักร'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      int insertedCount = 0;
      final machinesInDb = await DbHelper.query('SELECT machine_id, machine_no FROM machines');
      final machineMap = {for (var m in machinesInDb) m['machine_no']?.toString().toUpperCase(): m['machine_id']?.toString()};

      for (final row in _rawRows) {
        if (row.isEmpty) continue;
        final rawMc = _colMachine >= 0 && _colMachine < row.length ? row[_colMachine].toString().trim() : '';
        if (rawMc.isEmpty) continue;

        final matchedId = machineMap[rawMc.toUpperCase()] ?? machineMap.values.firstWhere((id) => id == rawMc, orElse: () => rawMc);
        final date = _colDate >= 0 && _colDate < row.length ? _parseDate(row[_colDate]) : DateTime.now();
        final hours = _colHours >= 0 && _colHours < row.length ? _parseDouble(row[_colHours], fallback: 8.0) : 8.0;
        final target = _colTarget >= 0 && _colTarget < row.length ? _parseDouble(row[_colTarget], fallback: 1000.0) : 1000.0;
        final actual = _colActual >= 0 && _colActual < row.length ? _parseDouble(row[_colActual], fallback: 950.0) : 950.0;
        final good = _colGood >= 0 && _colGood < row.length ? _parseDouble(row[_colGood], fallback: actual) : actual;

        final id = const Uuid().v4();
        await DbHelper.execute(
          '''INSERT INTO machine_running_hours (
              hours_id, machine_id, cumulative_hours, target_production, actual_production, good_production, recorded_date, data_source
             ) VALUES (
              @id, @mId, @hrs, @tgt, @act, @good, @date, 'excel_import'
             )''',
          params: {
            'id': id,
            'mId': matchedId,
            'hrs': hours,
            'tgt': target,
            'act': actual,
            'good': good,
            'date': date.toIso8601String(),
          },
        );
        insertedCount++;
      }

      ref.invalidate(maintenanceMetricsProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(oeeTrendProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ นำเข้าข้อมูล OEE สำเร็จ $insertedCount รายการ!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'บันทึกข้อมูลล้มเหลว: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 850,
        height: 650,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.table_view_rounded, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('นำเข้ายอดผลิต & OEE จาก Excel / CSV',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('อัปโหลดไฟล์ของโรงงาน ระบบจะจับคู่หัวคอลัมน์ให้อัตโนมัติ',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: _selectedFile == null
                  ? _buildUploadArea(theme)
                  : _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildMappingAndPreview(theme),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (_selectedFile != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('เลือกไฟล์ใหม่'),
                    onPressed: _isSaving ? null : _pickFile,
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('ยกเลิก'),
                ),
                const SizedBox(width: 8),
                if (_selectedFile != null && _rawRows.isNotEmpty)
                  FilledButton.icon(
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: Text(_isSaving ? 'กำลังบันทึก...' : 'ยืนยันนำเข้า  รายการ'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                    onPressed: _isSaving ? null : _saveData,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadArea(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.upload_file_rounded, size: 54, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text('เลือกไฟล์ Excel หรือ CSV จากเครื่องของคุณ', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('รองรับไฟล์ .xlsx, .xls, .csv ทุกโครงสร้างตาราง',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('เลือกไฟล์เพื่อนำเข้า'),
            onPressed: _pickFile,
          ),
        ],
      ),
    );
  }

  Widget _buildMappingAndPreview(ThemeData theme) {
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 18),
              const SizedBox(width: 8),
              Text('ไฟล์: ${_fileName ?? "-"}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Text('พบทั้งหมด ${_rawRows.length} แถว', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('1. ตรวจสอบการจับคู่หัวคอลัมน์ (Smart Auto-Mapping)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _buildDropdown('รหัสเครื่องจักร (Machine) *', _colMachine, (v) => setState(() => _colMachine = v ?? -1)),
              _buildDropdown('วันที่ผลิต (Date)', _colDate, (v) => setState(() => _colDate = v ?? -1)),
              _buildDropdown('ชั่วโมงเดินเครื่อง (Hours)', _colHours, (v) => setState(() => _colHours = v ?? -1)),
              _buildDropdown('ยอดเป้าหมาย (Target)', _colTarget, (v) => setState(() => _colTarget = v ?? -1)),
              _buildDropdown('ยอดผลิตจริง (Actual)', _colActual, (v) => setState(() => _colActual = v ?? -1)),
              _buildDropdown('ยอดของดี (Good Qty)', _colGood, (v) => setState(() => _colGood = v ?? -1)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('2. ตัวอย่างข้อมูลและผลคำนวณ OEE (Live Preview)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 38,
              dataRowMinHeight: 34,
              dataRowMaxHeight: 36,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('เครื่องจักร')),
                DataColumn(label: Text('วันที่')),
                DataColumn(label: Text('ชม.เดิน')),
                DataColumn(label: Text('เป้าหมาย')),
                DataColumn(label: Text('ผลิตจริง')),
                DataColumn(label: Text('ของดี')),
                DataColumn(label: Text('คำนวณ OEE')),
              ],
              rows: List.generate(
                _rawRows.length > 10 ? 10 : _rawRows.length,
                (index) {
                  final r = _rawRows[index];
                  final mc = _colMachine >= 0 && _colMachine < r.length ? r[_colMachine].toString() : '-';
                  final date = _colDate >= 0 && _colDate < r.length ? r[_colDate].toString() : '-';
                  final hrs = _colHours >= 0 && _colHours < r.length ? _parseDouble(r[_colHours], fallback: 8.0) : 8.0;
                  final tgt = _colTarget >= 0 && _colTarget < r.length ? _parseDouble(r[_colTarget], fallback: 1000.0) : 1000.0;
                  final act = _colActual >= 0 && _colActual < r.length ? _parseDouble(r[_colActual], fallback: 950.0) : 950.0;
                  final good = _colGood >= 0 && _colGood < r.length ? _parseDouble(r[_colGood], fallback: act) : act;

                  final avail = hrs > 0 ? (hrs / (hrs + 0.5)) : 0.0;
                  final perf = tgt > 0 ? (act / tgt) : 0.0;
                  final qual = act > 0 ? (good / act) : 0.0;
                  final oee = (avail * perf * qual * 100).clamp(0, 100);

                  return DataRow(
                    cells: [
                      DataCell(Text('')),
                      DataCell(Text(mc, style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(date)),
                      DataCell(Text('h')),
                      DataCell(Text(tgt.toStringAsFixed(0))),
                      DataCell(Text(act.toStringAsFixed(0))),
                      DataCell(Text(good.toStringAsFixed(0))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: oee >= 85 ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: oee >= 85 ? Colors.green.shade800 : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, int selectedIndex, ValueChanged<int?> onChanged) {
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            value: selectedIndex >= 0 && selectedIndex < _headers.length ? selectedIndex : null,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            hint: const Text('เลือกคอลัมน์...', style: TextStyle(fontSize: 12)),
            items: List.generate(
              _headers.length,
              (idx) => DropdownMenuItem(
                value: idx,
                child: Text(
                  _headers[idx].isNotEmpty ? _headers[idx] : 'คอลัมน์ ${idx + 1}',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
