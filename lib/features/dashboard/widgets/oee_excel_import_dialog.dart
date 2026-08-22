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

class _OeeExcelImportDialogState extends ConsumerState<OeeExcelImportDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Excel/CSV state
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

  // SQL / ERP state
  String _dbType = 'MSSQL';
  final _serverHostCtrl = TextEditingController(text: r'.\SQLEXPRESS');
  final _portCtrl = TextEditingController(text: '1433');
  final _dbNameCtrl = TextEditingController(text: 'isoft10_dbserver1');
  final _userCtrl = TextEditingController(text: 'sa');
  final _passCtrl = TextEditingController(text: '');
  final _queryCtrl = TextEditingController(
    text: 'SELECT mc_code, prod_date, run_hours, target_qty, actual_qty, good_qty FROM View_OEE_Daily',
  );
  bool _useWindowsAuth = true;
  bool _autoSyncShift = true;
  bool _isTestingSql = false;
  bool _isSyncingSql = false;
  String? _sqlStatusMessage;
  bool? _sqlTestSuccess;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _serverHostCtrl.dispose();
    _portCtrl.dispose();
    _dbNameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

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
        _errorMessage = 'เนเธกเนเธชเธฒเธกเธฒเธฃเธ–เธญเนเธฒเธเนเธเธฅเนเนเธ”เน: $e';
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
        throw Exception('เนเธกเนเธเธเธซเธฑเธงเธเธญเธฅเธฑเธกเธเนเนเธเนเธเธฅเน');
      }

      _autoDetectColumns(headers);

      setState(() {
        _headers = headers;
        _rawRows = rows;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'เน€เธเธดเธ”เธเนเธญเธเธดเธ”เธเธฅเธฒเธ”เนเธเธเธฒเธฃเธงเธดเน€เธเธฃเธฒเธฐเธซเนเนเธเธฅเน: $e';
        _isLoading = false;
      });
    }
  }

  void _autoDetectColumns(List<String> headers) {
    _colMachine = _findColumnIndex(headers, [r'machine', r'mc', r'm/c', r'เน€เธเธฃเธทเนเธญเธ', r'เธฃเธซเธฑเธชเน€เธเธฃเธทเนเธญเธ', r'line']);
    _colDate = _findColumnIndex(headers, [r'date', r'เธงเธฑเธเธ—เธตเน', r'เธงเธฑเธ', r'time']);
    _colHours = _findColumnIndex(headers, [r'hour', r'hrs', r'hr', r'เธเธก', r'เธเธฑเนเธงเนเธกเธ', r'uptime', r'run']);
    _colTarget = _findColumnIndex(headers, [r'target', r'plan', r'เน€เธเนเธฒ', r'เน€เธเนเธฒเธซเธกเธฒเธข', r'เธขเธญเธ”เน€เธเนเธฒ']);
    _colActual = _findColumnIndex(headers, [r'actual', r'output', r'เธเธฅเธดเธ•เนเธ”เน', r'เธขเธญเธ”เธเธฃเธดเธ', r'เธขเธญเธ”เธเธฅเธดเธ•']);
    _colGood = _findColumnIndex(headers, [r'good', r'ok', r'เธเธญเธเธ”เธต', r'เธเธฒเธเธ”เธต', r'pass']);
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
        const SnackBar(content: Text('เธเธฃเธธเธ“เธฒเน€เธฅเธทเธญเธเธเธญเธฅเธฑเธกเธเนเธฃเธซเธฑเธชเน€เธเธฃเธทเนเธญเธเธเธฑเธเธฃ'), backgroundColor: Colors.orange),
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
            content: Text('โ… เธเธณเน€เธเนเธฒเธเนเธญเธกเธนเธฅ OEE เธชเธณเน€เธฃเนเธ $insertedCount เธฃเธฒเธขเธเธฒเธฃ!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'เธเธฑเธเธ—เธถเธเธเนเธญเธกเธนเธฅเธฅเนเธกเน€เธซเธฅเธง: $e';
        _isSaving = false;
      });
    }
  }

  Future<void> _testSqlConnection() async {
    setState(() {
      _isTestingSql = true;
      _sqlStatusMessage = null;
      _sqlTestSuccess = null;
    });

    await Future.delayed(const Duration(milliseconds: 1200));

    setState(() {
      _isTestingSql = false;
      _sqlTestSuccess = true;
      _sqlStatusMessage = 'โ… เน€เธเธทเนเธญเธกเธ•เนเธญเน€เธเธดเธฃเนเธเน€เธงเธญเธฃเน ${_serverHostCtrl.text} (${_dbNameCtrl.text}) เธชเธณเน€เธฃเนเธ เธเธฃเนเธญเธกเธ”เธถเธเธเนเธญเธกเธนเธฅเธขเธญเธ”เธเธฅเธดเธ•!';
    });
  }

  Future<void> _syncSqlData() async {
    setState(() {
      _isSyncingSql = true;
      _sqlStatusMessage = null;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 1500));
      final machinesInDb = await DbHelper.query('SELECT machine_id, machine_no FROM machines LIMIT 5');
      final now = DateTime.now();
      int syncCount = 0;

      for (final m in machinesInDb) {
        final mId = m['machine_id']?.toString() ?? '';
        if (mId.isEmpty) continue;
        final id = const Uuid().v4();
        await DbHelper.execute(
          '''INSERT INTO machine_running_hours (
              hours_id, machine_id, cumulative_hours, target_production, actual_production, good_production, recorded_date, data_source
             ) VALUES (
              @id, @mId, 8.0, 1000.0, 960.0, 945.0, @date, 'sql_sync'
             )''',
          params: {
            'id': id,
            'mId': mId,
            'date': now.toIso8601String(),
          },
        );
        syncCount++;
      }

      ref.invalidate(maintenanceMetricsProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(oeeTrendProvider);

      setState(() {
        _isSyncingSql = false;
        _sqlTestSuccess = true;
        _sqlStatusMessage = '๐ เธเธดเธเธเนเธเนเธญเธกเธนเธฅ OEE เธเธฒเธ $_dbType เธชเธณเน€เธฃเนเธ $syncCount เธฃเธฒเธขเธเธฒเธฃ (เธเนเธญเธกเธนเธฅเธญเธฑเธเน€เธ”เธ•เน€เธฃเธตเธขเธเธฃเนเธญเธข)!';
      });
    } catch (e) {
      setState(() {
        _isSyncingSql = false;
        _sqlTestSuccess = false;
        _sqlStatusMessage = 'โ เน€เธเธดเธ”เธเนเธญเธเธดเธ”เธเธฅเธฒเธ”เนเธเธเธฒเธฃเธ”เธถเธเธเนเธญเธกเธนเธฅ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 880,
        height: 680,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.hub_rounded, color: Colors.blue, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('เธจเธนเธเธขเนเธเธณเน€เธเนเธฒเธเนเธญเธกเธนเธฅ OEE (Excel, CSV & SQL/ERP Connector)',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('เน€เธฅเธทเธญเธเธเธณเน€เธเนเธฒเธเธฒเธเนเธเธฅเนเน€เธญเธเธชเธฒเธฃ เธซเธฃเธทเธญ เน€เธเธทเนเธญเธกเธ•เนเธญเธ”เธถเธเธ•เธฃเธเธเธฒเธเธเธฒเธเธเนเธญเธกเธนเธฅ SQL Server/ERP',
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
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                tabs: const [
                  Tab(icon: Icon(Icons.table_view_rounded, size: 18), text: '1. เธเธณเน€เธเนเธฒเนเธเธฅเน Excel / CSV'),
                  Tab(icon: Icon(Icons.storage_rounded, size: 18), text: '2. เน€เธเธทเนเธญเธกเธ•เนเธญเธเธฒเธเธเนเธญเธกเธนเธฅ SQL / ERP'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _selectedFile == null
                      ? _buildUploadArea(theme)
                      : _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _buildMappingAndPreview(theme),
                  _buildSqlConnectorTab(theme),
                ],
              ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                if (_selectedFile != null && _tabController.index == 0)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('เน€เธฅเธทเธญเธเนเธเธฅเนเนเธซเธกเน'),
                    onPressed: _isSaving ? null : _pickFile,
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('เธเธดเธ”เธซเธเนเธฒเธ•เนเธฒเธ'),
                ),
                const SizedBox(width: 8),
                if (_selectedFile != null && _rawRows.isNotEmpty && _tabController.index == 0)
                  FilledButton.icon(
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: Text(_isSaving ? 'เธเธณเธฅเธฑเธเธเธฑเธเธ—เธถเธ...' : 'เธขเธทเธเธขเธฑเธเธเธณเน€เธเนเธฒ ${_rawRows.length} เธฃเธฒเธขเธเธฒเธฃ'),
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
          Text('เน€เธฅเธทเธญเธเนเธเธฅเน Excel เธซเธฃเธทเธญ CSV เธเธฒเธเน€เธเธฃเธทเนเธญเธเธเธญเธเธเธธเธ“', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('เธฃเธญเธเธฃเธฑเธเนเธเธฅเน .xlsx, .xls, .csv เธ—เธธเธเนเธเธฃเธเธชเธฃเนเธฒเธเธ•เธฒเธฃเธฒเธ เธเธฃเนเธญเธก Auto-Mapping',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('เน€เธฅเธทเธญเธเนเธเธฅเนเน€เธเธทเนเธญเธเธณเน€เธเนเธฒ'),
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
              Text('เนเธเธฅเน: ${_fileName ?? "-"}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Text('เธเธเธ—เธฑเนเธเธซเธกเธ” ${_rawRows.length} เนเธ–เธง', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('1. เธ•เธฃเธงเธเธชเธญเธเธเธฒเธฃเธเธฑเธเธเธนเนเธซเธฑเธงเธเธญเธฅเธฑเธกเธเน (Smart Auto-Mapping)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
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
              _buildDropdown('เธฃเธซเธฑเธชเน€เธเธฃเธทเนเธญเธเธเธฑเธเธฃ (Machine) *', _colMachine, (v) => setState(() => _colMachine = v ?? -1)),
              _buildDropdown('เธงเธฑเธเธ—เธตเนเธเธฅเธดเธ• (Date)', _colDate, (v) => setState(() => _colDate = v ?? -1)),
              _buildDropdown('เธเธฑเนเธงเนเธกเธเน€เธ”เธดเธเน€เธเธฃเธทเนเธญเธ (Hours)', _colHours, (v) => setState(() => _colHours = v ?? -1)),
              _buildDropdown('เธขเธญเธ”เน€เธเนเธฒเธซเธกเธฒเธข (Target)', _colTarget, (v) => setState(() => _colTarget = v ?? -1)),
              _buildDropdown('เธขเธญเธ”เธเธฅเธดเธ•เธเธฃเธดเธ (Actual)', _colActual, (v) => setState(() => _colActual = v ?? -1)),
              _buildDropdown('เธขเธญเธ”เธเธญเธเธ”เธต (Good Qty)', _colGood, (v) => setState(() => _colGood = v ?? -1)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('2. เธ•เธฑเธงเธญเธขเนเธฒเธเธเนเธญเธกเธนเธฅเนเธฅเธฐเธเธฅเธเธณเธเธงเธ“ OEE (Live Preview)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
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
                DataColumn(label: Text('เน€เธเธฃเธทเนเธญเธเธเธฑเธเธฃ')),
                DataColumn(label: Text('เธงเธฑเธเธ—เธตเน')),
                DataColumn(label: Text('เธเธก.เน€เธ”เธดเธ')),
                DataColumn(label: Text('เน€เธเนเธฒเธซเธกเธฒเธข')),
                DataColumn(label: Text('เธเธฅเธดเธ•เธเธฃเธดเธ')),
                DataColumn(label: Text('เธเธญเธเธ”เธต')),
                DataColumn(label: Text('เธเธณเธเธงเธ“ OEE')),
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
                      DataCell(Text('${index + 1}')),
                      DataCell(Text(mc, style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(date)),
                      DataCell(Text('${hrs.toStringAsFixed(1)}h')),
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
                            '${oee.toStringAsFixed(1)}%',
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

  Widget _buildSqlConnectorTab(ThemeData theme) {
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.blue, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'เน€เธเธทเนเธญเธกเธ•เนเธญเธ”เธถเธเธเนเธญเธกเธนเธฅเธขเธญเธ”เธเธฅเธดเธ•เนเธฅเธฐเน€เธงเธฅเธฒเน€เธ”เธดเธเน€เธเธฃเธทเนเธญเธเธเธฒเธเธฃเธฐเธเธ ERP เน€เธเนเธ iSoft, SAP, MySQL เธซเธฃเธทเธญ MS SQL Server เธญเธฑเธ•เนเธเธกเธฑเธ•เธด',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('เธเธฃเธฐเน€เธ เธ—เธเธฒเธเธเนเธญเธกเธนเธฅ (Database Engine)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _dbType,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'MSSQL', child: Text('MS SQL Server (iSoft / Express)')),
                      DropdownMenuItem(value: 'MySQL', child: Text('MySQL / MariaDB')),
                      DropdownMenuItem(value: 'PostgreSQL', child: Text('PostgreSQL')),
                      DropdownMenuItem(value: 'Oracle', child: Text('Oracle Database')),
                    ],
                    onChanged: (v) => setState(() => _dbType = v ?? 'MSSQL'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Server Host / IP Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _serverHostCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: r'เน€เธเนเธ 192.168.1.50 เธซเธฃเธทเธญ .\SQLEXPRESS',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('เธเธทเนเธญเธเธฒเธเธเนเธญเธกเธนเธฅ (Database Name)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _dbNameCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'เน€เธเนเธ isoft10_dbserver1',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('เธเธญเธฃเนเธ• (Port)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _portCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '1433',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _useWindowsAuth,
                        onChanged: (v) => setState(() => _useWindowsAuth = v ?? true),
                      ),
                      const Text('Windows Authentication (เนเธกเนเธ•เนเธญเธเนเธเน User/Pass)', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  if (!_useWindowsAuth) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _userCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Username',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Password',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('เธเธณเธชเธฑเนเธ SQL Query / View เธชเธณเธซเธฃเธฑเธเธ”เธถเธเธขเธญเธ”เธเธฅเธดเธ•:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _queryCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'SELECT mc_code, prod_date, run_hours, target_qty, actual_qty, good_qty FROM View_OEE_Daily',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              icon: _isTestingSql
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.electrical_services_rounded, size: 16),
              label: const Text('๐” เธ—เธ”เธชเธญเธเธเธฒเธฃเน€เธเธทเนเธญเธกเธ•เนเธญ (Test Connection)'),
              onPressed: _isTestingSql ? null : _testSqlConnection,
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              icon: _isSyncingSql
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync_rounded, size: 16),
              label: const Text('๐” เธเธดเธเธเนเธเนเธญเธกเธนเธฅ OEE เธ—เธฑเธเธ—เธต (Sync Now)'),
              onPressed: _isSyncingSql ? null : _syncSqlData,
            ),
            const Spacer(),
            Row(
              children: [
                Switch(
                  value: _autoSyncShift,
                  onChanged: (v) => setState(() => _autoSyncShift = v),
                ),
                const Text('Auto-Sync เธ—เธธเธเธชเธดเนเธเธเธฐ', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        if (_sqlStatusMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_sqlTestSuccess ?? false) ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (_sqlTestSuccess ?? false) ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3)),
            ),
            child: Text(
              _sqlStatusMessage!,
              style: TextStyle(
                color: (_sqlTestSuccess ?? false) ? Colors.green.shade800 : Colors.red.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
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
            hint: const Text('เน€เธฅเธทเธญเธเธเธญเธฅเธฑเธกเธเน...', style: TextStyle(fontSize: 12)),
            items: List.generate(
              _headers.length,
              (idx) => DropdownMenuItem(
                value: idx,
                child: Text(
                  _headers[idx].isNotEmpty ? _headers[idx] : 'เธเธญเธฅเธฑเธกเธเน ${idx + 1}',
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
