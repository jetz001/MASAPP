import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/db_helper.dart';

class OutsourceVendorScreen extends StatefulWidget {
  const OutsourceVendorScreen({super.key});

  @override
  State<OutsourceVendorScreen> createState() => _OutsourceVendorScreenState();
}

class _OutsourceVendorScreenState extends State<OutsourceVendorScreen> {
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
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController(
      text: vendor?['supplier_code'] as String? ?? '',
    );
    final name = TextEditingController(text: vendor?['name'] as String? ?? '');
    final contact = TextEditingController(
      text: vendor?['contact_name'] as String? ?? '',
    );
    final phone = TextEditingController(
      text: vendor?['phone'] as String? ?? '',
    );
    final email = TextEditingController(
      text: vendor?['email'] as String? ?? '',
    );
    final scope = TextEditingController(
      text: vendor?['service_scope'] as String? ?? '',
    );
    final address = TextEditingController(
      text: vendor?['address'] as String? ?? '',
    );
    var approved = (vendor?['is_approved'] as num? ?? 0) == 1;
    var vendorType = vendor?['vendor_type'] as String? ?? 'repair';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            vendor == null
                ? 'เพิ่มผู้รับเหมาซ่อมภายนอก'
                : 'แก้ไขข้อมูลผู้รับเหมา',
          ),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      [
                            TextFormField(
                              controller: code,
                              decoration: const InputDecoration(
                                labelText: 'รหัสผู้รับเหมา *',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'กรุณาระบุรหัส'
                                  : null,
                            ),
                            TextFormField(
                              controller: name,
                              decoration: const InputDecoration(
                                labelText: 'ชื่อบริษัท / ร้าน *',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'กรุณาระบุชื่อ'
                                  : null,
                            ),
                            TextFormField(
                              controller: scope,
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
                                  icon: Icon(
                                    Icons.miscellaneous_services_outlined,
                                  ),
                                ),
                              ],
                              selected: {vendorType},
                              onSelectionChanged: (value) => setDialogState(
                                () => vendorType = value.first,
                              ),
                            ),
                            TextFormField(
                              controller: contact,
                              decoration: const InputDecoration(
                                labelText: 'ผู้ติดต่อ',
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: phone,
                                    decoration: const InputDecoration(
                                      labelText: 'โทรศัพท์',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: email,
                                    decoration: const InputDecoration(
                                      labelText: 'อีเมล',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TextFormField(
                              controller: address,
                              decoration: const InputDecoration(
                                labelText: 'ที่อยู่',
                              ),
                              maxLines: 2,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('อนุมัติให้ส่งงานซ่อมได้'),
                              value: approved,
                              onChanged: (v) =>
                                  setDialogState(() => approved = v),
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
                if (!formKey.currentState!.validate()) return;
                final values = {
                  'code': code.text.trim(),
                  'name': name.text.trim(),
                  'scope': scope.text.trim(),
                  'type': vendorType,
                  'contact': contact.text.trim(),
                  'phone': phone.text.trim(),
                  'email': email.text.trim(),
                  'address': address.text.trim(),
                  'approved': approved ? 1 : 0,
                };
                if (vendor == null) {
                  await DbHelper.execute(
                    '''INSERT INTO suppliers (supplier_id, supplier_code, name, contact_name, phone, email, address, service_scope, vendor_type, is_outsource_vendor, is_approved, is_active) VALUES (@id, @code, @name, @contact, @phone, @email, @address, @scope, @type, 1, @approved, 1)''',
                    params: {...values, 'id': const Uuid().v4()},
                  );
                } else {
                  await DbHelper.execute(
                    '''UPDATE suppliers SET supplier_code=@code, name=@name, contact_name=@contact, phone=@phone, email=@email, address=@address, service_scope=@scope, vendor_type=@type, is_approved=@approved WHERE supplier_id=@id''',
                    params: {...values, 'id': vendor['supplier_id']},
                  );
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      code,
      name,
      contact,
      phone,
      email,
      scope,
      address,
    ]) {
      controller.dispose();
    }
    if (saved == true) _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> vendor) async {
    final isActive = (vendor['is_active'] as num? ?? 0) == 1;
    await DbHelper.execute(
      'UPDATE suppliers SET is_active = @active WHERE supplier_id = @id',
      params: {'active': isActive ? 0 : 1, 'id': vendor['supplier_id']},
    );
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                label: Text(
                                  _typeLabel(vendor['vendor_type'] as String?),
                                ),
                              ),
                              Chip(
                                label: Text(
                                  approved ? 'อนุมัติแล้ว' : 'รออนุมัติ',
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _showForm(vendor),
                              ),
                              TextButton(
                                onPressed: () => _toggleActive(vendor),
                                child: Text(
                                  active ? 'พักใช้งาน' : 'เปิดใช้งาน',
                                ),
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

  String _typeLabel(String? value) => switch (value) {
    'supply' => 'จัดหา/อะไหล่',
    'other' => 'บริการอื่น',
    _ => 'รับซ่อม',
  };
}
