import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/db_helper.dart';
import '../../features/auth/auth_provider.dart';
import 'outsource_vendor_log_sheet_pdf_service.dart';

class OutsourceVendorScreen extends ConsumerStatefulWidget {
  const OutsourceVendorScreen({super.key});

  @override
  ConsumerState<OutsourceVendorScreen> createState() => _OutsourceVendorScreenState();
}

class _OutsourceVendorScreenState extends ConsumerState<OutsourceVendorScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _vendors = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final keyword = _searchController.text.trim();
      final rows = await DbHelper.query(
        '''SELECT supplier_id, supplier_code, name, contact_name, phone, email,
                  address, service_scope, vendor_type, is_approved, is_active
           FROM suppliers
           WHERE is_outsource_vendor = 1
             AND (@keyword = '' OR name LIKE @like OR supplier_code LIKE @like OR service_scope LIKE @like)
           ORDER BY is_active DESC, name''',
        params: {'keyword': keyword, 'like': '%$keyword%'},
      );
      if (mounted) setState(() => _vendors = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForm([Map<String, dynamic>? vendor]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _OutsourceVendorFormDialog(vendor: vendor),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleApprove(Map<String, dynamic> vendor) async {
    final isApproved = (vendor['is_approved'] as num? ?? 0) == 1;
    final newStatus = isApproved ? 0 : 1;
    await DbHelper.execute(
      'UPDATE suppliers SET is_approved = @approved WHERE supplier_id = @id',
      params: {'approved': newStatus, 'id': vendor['supplier_id']},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 1
                ? 'อนุมัติผู้รับเหมา "${vendor['name']}" เรียบร้อยแล้ว'
                : 'ยกเลิกการอนุมัติผู้รับเหมา "${vendor['name']}" แล้ว',
          ),
          backgroundColor: newStatus == 1 ? Colors.green : Colors.orange,
        ),
      );
    }
    _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> vendor) async {
    final isActive = (vendor['is_active'] as num? ?? 0) == 1;
    await DbHelper.execute(
      'UPDATE suppliers SET is_active = @active WHERE supplier_id = @id',
      params: {'active': isActive ? 0 : 1, 'id': vendor['supplier_id']},
    );
    _load();
  }

  Future<void> _deleteVendor(Map<String, dynamic> vendor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('คุณต้องการลบผู้รับเหมา "${vendor['name']}" ใช่หรือไม่?\n\n*หมายเหตุ: หากผู้รับเหมาถูกอ้างอิงในใบแจ้งซ่อมแล้ว จะไม่สามารถลบได้ (แนะนำให้กดพักใช้งานแทน)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบข้อมูล'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DbHelper.execute(
        'DELETE FROM suppliers WHERE supplier_id = @id',
        params: {'id': vendor['supplier_id']},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ลบข้อมูลเรียบร้อยแล้ว')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไม่สามารถลบได้: อาจมีการใช้งานผู้รับเหมานี้อยู่แล้ว')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    
    return Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ทะเบียนผู้รับเหมาซ่อมภายนอก',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('รายชื่อผู้รับเหมาที่ใช้สำหรับส่งซ่อมและตรวจรับงาน'),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => OutsourceVendorLogSheetPdfService.generateAndOpen(keyword: _searchController.text.trim()),
                icon: const Icon(Icons.print_outlined),
                label: const Text('พิมพ์ทะเบียน'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _showForm(),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มผู้รับเหมา'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 360,
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _load(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ค้นหาชื่อ รหัส หรือประเภทงาน',
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _vendors.isEmpty
                ? const Center(child: Text('ยังไม่มีผู้รับเหมาซ่อมภายนอก'))
                : ListView.separated(
                    itemCount: _vendors.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final vendor = _vendors[index];
                      final active = (vendor['is_active'] as num? ?? 0) == 1;
                      final approved =
                          (vendor['is_approved'] as num? ?? 0) == 1;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(active ? Icons.business : Icons.pause),
                          ),
                          title: Text(
                            '${vendor['supplier_code']}  •  ${vendor['name']}',
                          ),
                          subtitle: Text(
                            '${vendor['service_scope'] ?? '-'}\n${vendor['contact_name'] ?? '-'}  ${vendor['phone'] ?? ''}',
                          ),
                          isThreeLine: true,
                          onTap: () => context.push('/outsource-vendors/${vendor['supplier_id']}').then((_) => _load()),
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                label: Text(
                                  _typeLabel(vendor['vendor_type'] as String?),
                                ),
                              ),
                              if (!approved)
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  ),
                                  onPressed: () => _toggleApprove(vendor),
                                  icon: const Icon(Icons.check_circle_outline, size: 18),
                                  label: const Text('อนุมัติ'),
                                )
                              else
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green.shade700,
                                    side: BorderSide(color: Colors.green.shade700),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  ),
                                  onPressed: () => _toggleApprove(vendor),
                                  icon: const Icon(Icons.verified, size: 16, color: Colors.green),
                                  label: const Text('อนุมัติแล้ว'),
                                ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'แก้ไข',
                                onPressed: () => _showForm(vendor),
                              ),
                              TextButton(
                                onPressed: () => _toggleActive(vendor),
                                child: Text(
                                  active ? 'พักใช้งาน' : 'เปิดใช้งาน',
                                ),
                              ),
                              if (user?.isAdmin == true)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _deleteVendor(vendor),
                                  tooltip: 'ลบผู้รับเหมา',
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
  }

  String _typeLabel(String? value) => switch (value) {
    'supply' => 'จัดหา/อะไหล่',
    'other' => 'บริการอื่น',
    _ => 'รับซ่อม',
  };
}

class _OutsourceVendorFormDialog extends StatefulWidget {
  final Map<String, dynamic>? vendor;

  const _OutsourceVendorFormDialog({this.vendor});

  @override
  State<_OutsourceVendorFormDialog> createState() =>
      _OutsourceVendorFormDialogState();
}

class _OutsourceVendorFormDialogState
    extends State<_OutsourceVendorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _contact;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _scope;
  late final TextEditingController _address;
  late bool _approved;
  late String _vendorType;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(
      text: widget.vendor?['supplier_code'] as String? ?? '',
    );
    _name = TextEditingController(
      text: widget.vendor?['name'] as String? ?? '',
    );
    _contact = TextEditingController(
      text: widget.vendor?['contact_name'] as String? ?? '',
    );
    _phone = TextEditingController(
      text: widget.vendor?['phone'] as String? ?? '',
    );
    _email = TextEditingController(
      text: widget.vendor?['email'] as String? ?? '',
    );
    _scope = TextEditingController(
      text: widget.vendor?['service_scope'] as String? ?? '',
    );
    _address = TextEditingController(
      text: widget.vendor?['address'] as String? ?? '',
    );
    _approved = (widget.vendor?['is_approved'] as num? ?? 0) == 1;
    _vendorType = widget.vendor?['vendor_type'] as String? ?? 'repair';
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _scope.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.vendor == null
            ? 'เพิ่มผู้รับเหมาซ่อมภายนอก'
            : 'แก้ไขข้อมูลผู้รับเหมา',
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'รหัสผู้รับเหมา *',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'กรุณาระบุรหัส' : null,
                ),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อบริษัท / ร้าน *',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'กรุณาระบุชื่อ' : null,
                ),
                TextFormField(
                  controller: _scope,
                  decoration: const InputDecoration(
                    labelText: 'ขอบเขตงานซ่อม *',
                    hintText: 'เช่น มอเตอร์, ไฮดรอลิก, CNC',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'กรุณาระบุขอบเขตงาน'
                      : null,
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'repair',
                      label: Text('รับซ่อม'),
                      icon: Icon(Icons.build_outlined),
                    ),
                    ButtonSegment(
                      value: 'supply',
                      label: Text('จัดหา/อะไหล่'),
                      icon: Icon(Icons.inventory_2_outlined),
                    ),
                    ButtonSegment(
                      value: 'other',
                      label: Text('บริการอื่น'),
                      icon: Icon(Icons.miscellaneous_services_outlined),
                    ),
                  ],
                  selected: {_vendorType},
                  onSelectionChanged: (value) => setState(
                    () => _vendorType = value.first,
                  ),
                ),
                TextFormField(
                  controller: _contact,
                  decoration: const InputDecoration(
                    labelText: 'ผู้ติดต่อ',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        decoration: const InputDecoration(
                          labelText: 'โทรศัพท์',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(
                          labelText: 'อีเมล',
                        ),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'ที่อยู่',
                  ),
                  maxLines: 2,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('อนุมัติให้ส่งงานซ่อมได้'),
                  value: _approved,
                  onChanged: (v) => setState(() => _approved = v),
                ),
              ]
                  .map(
                    (field) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: field,
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final values = {
              'code': _code.text.trim(),
              'name': _name.text.trim(),
              'scope': _scope.text.trim(),
              'type': _vendorType,
              'contact': _contact.text.trim(),
              'phone': _phone.text.trim(),
              'email': _email.text.trim(),
              'address': _address.text.trim(),
              'approved': _approved ? 1 : 0,
            };
            if (widget.vendor == null) {
              await DbHelper.execute(
                '''INSERT INTO suppliers (supplier_id, supplier_code, name, contact_name, phone, email, address, service_scope, vendor_type, is_outsource_vendor, is_approved, is_active) VALUES (@id, @code, @name, @contact, @phone, @email, @address, @scope, @type, 1, @approved, 1)''',
                params: {...values, 'id': const Uuid().v4()},
              );
            } else {
              await DbHelper.execute(
                '''UPDATE suppliers SET supplier_code=@code, name=@name, contact_name=@contact, phone=@phone, email=@email, address=@address, service_scope=@scope, vendor_type=@type, is_approved=@approved WHERE supplier_id=@id''',
                params: {...values, 'id': widget.vendor!['supplier_id']},
              );
            }
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}

