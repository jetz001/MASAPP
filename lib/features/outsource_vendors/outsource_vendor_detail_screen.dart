import 'package:flutter/material.dart';
import '../../core/database/db_helper.dart';
import 'outsource_vendor_pdf_service.dart';

class OutsourceVendorDetailScreen extends StatefulWidget {
  final String id;
  const OutsourceVendorDetailScreen({super.key, required this.id});

  @override
  State<OutsourceVendorDetailScreen> createState() => _OutsourceVendorDetailScreenState();
}

class _OutsourceVendorDetailScreenState extends State<OutsourceVendorDetailScreen> {
  Map<String, dynamic>? _vendor;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DbHelper.query(
      'SELECT * FROM suppliers WHERE supplier_id = @id',
      params: {'id': widget.id},
    );
    if (mounted) {
      setState(() {
        if (rows.isNotEmpty) _vendor = rows.first;
        _loading = false;
      });
    }
  }

  Future<void> _toggleApprove() async {
    if (_vendor == null) return;
    final isApproved = (_vendor!['is_approved'] as num? ?? 0) == 1;
    final newStatus = isApproved ? 0 : 1;
    await DbHelper.execute(
      'UPDATE suppliers SET is_approved = @approved WHERE supplier_id = @id',
      params: {'approved': newStatus, 'id': widget.id},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 1
                ? 'อนุมัติผู้รับเหมาเรียบร้อยแล้ว'
                : 'ยกเลิกการอนุมัติผู้รับเหมาแล้ว',
          ),
          backgroundColor: newStatus == 1 ? Colors.green : Colors.orange,
        ),
      );
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_vendor == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ไม่พบข้อมูล')),
        body: const Center(child: Text('ไม่พบข้อมูลผู้รับเหมา')),
      );
    }

    final vendor = _vendor!;
    final type = vendor['vendor_type'] == 'supply' ? 'จัดหา/อะไหล่' : vendor['vendor_type'] == 'other' ? 'บริการอื่น' : 'รับซ่อม';
    final approved = (vendor['is_approved'] as num? ?? 0) == 1;
    final active = (vendor['is_active'] as num? ?? 0) == 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ข้อมูลผู้รับเหมา'),
        actions: [
          if (!approved)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('อนุมัติผู้รับเหมา'),
                onPressed: _toggleApprove,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade700),
                ),
                icon: const Icon(Icons.verified, size: 18, color: Colors.green),
                label: const Text('อนุมัติแล้ว'),
                onPressed: _toggleApprove,
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'พิมพ์ข้อมูลผู้รับเหมา',
            onPressed: () => OutsourceVendorPdfService.generateAndOpen(vendorId: widget.id),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'แก้ไข',
            onPressed: () => _showForm(vendor),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vendor['name'] ?? '',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (approved)
                        const Chip(
                          avatar: Icon(Icons.check_circle, color: Colors.green, size: 18),
                          label: Text('อนุมัติแล้ว', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        )
                      else
                        const Chip(
                          avatar: Icon(Icons.hourglass_empty, color: Colors.orange, size: 18),
                          label: Text('รออนุมัติ', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('รหัส: ${vendor['supplier_code'] ?? '-'}'),
                  const Divider(height: 32),
                  _buildDetailRow('ประเภท', type),
                  _buildDetailRow('ขอบเขตงาน', vendor['service_scope'] ?? '-'),
                  _buildDetailRow('ผู้ติดต่อ', vendor['contact_name'] ?? '-'),
                  _buildDetailRow('เบอร์โทรศัพท์', vendor['phone'] ?? '-'),
                  _buildDetailRow('อีเมล', vendor['email'] ?? '-'),
                  _buildDetailRow('ที่อยู่', vendor['address'] ?? '-'),
                  const Divider(height: 32),
                  _buildDetailRow('สถานะการอนุมัติ', approved ? 'อนุมัติแล้ว' : 'รออนุมัติ'),
                  _buildDetailRow('สถานะการใช้งาน', active ? 'เปิดใช้งาน' : 'พักใช้งาน'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!approved)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('กดเพื่ออนุมัติผู้รับเหมานี้'),
                          onPressed: _toggleApprove,
                        )
                      else
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                          icon: const Icon(Icons.undo),
                          label: const Text('ยกเลิกการอนุมัติ'),
                          onPressed: _toggleApprove,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _showForm(Map<String, dynamic> vendor) async {
    final formKey = GlobalKey<FormState>();
    final code = TextEditingController(text: vendor['supplier_code'] as String? ?? '');
    final name = TextEditingController(text: vendor['name'] as String? ?? '');
    final contact = TextEditingController(text: vendor['contact_name'] as String? ?? '');
    final phone = TextEditingController(text: vendor['phone'] as String? ?? '');
    final email = TextEditingController(text: vendor['email'] as String? ?? '');
    final scope = TextEditingController(text: vendor['service_scope'] as String? ?? '');
    final address = TextEditingController(text: vendor['address'] as String? ?? '');
    var approved = (vendor['is_approved'] as num? ?? 0) == 1;
    var vendorType = vendor['vendor_type'] as String? ?? 'repair';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('แก้ไขข้อมูลผู้รับเหมา'),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: code,
                      decoration: const InputDecoration(labelText: 'รหัสผู้รับเหมา *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'กรุณาระบุรหัส' : null,
                    ),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'ชื่อบริษัท / ร้าน *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'กรุณาระบุชื่อ' : null,
                    ),
                    TextFormField(
                      controller: scope,
                      decoration: const InputDecoration(labelText: 'ขอบเขตงานซ่อม *', hintText: 'เช่น มอเตอร์, ไฮดรอลิก, CNC'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'กรุณาระบุขอบเขตงาน' : null,
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'repair', label: Text('รับซ่อม'), icon: Icon(Icons.build_outlined)),
                        ButtonSegment(value: 'supply', label: Text('จัดหา/อะไหล่'), icon: Icon(Icons.inventory_2_outlined)),
                        ButtonSegment(value: 'other', label: Text('บริการอื่น'), icon: Icon(Icons.miscellaneous_services_outlined)),
                      ],
                      selected: {vendorType},
                      onSelectionChanged: (value) => setDialogState(() => vendorType = value.first),
                    ),
                    TextFormField(controller: contact, decoration: const InputDecoration(labelText: 'ผู้ติดต่อ')),
                    Row(
                      children: [
                        Expanded(child: TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'โทรศัพท์'))),
                        const SizedBox(width: 12),
                        Expanded(child: TextFormField(controller: email, decoration: const InputDecoration(labelText: 'อีเมล'))),
                      ],
                    ),
                    TextFormField(controller: address, decoration: const InputDecoration(labelText: 'ที่อยู่'), maxLines: 2),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('อนุมัติให้ส่งงานซ่อมได้'),
                      value: approved,
                      onChanged: (v) => setDialogState(() => approved = v),
                    ),
                  ].map((field) => Padding(padding: const EdgeInsets.only(bottom: 12), child: field)).toList(),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await DbHelper.execute(
                  '''UPDATE suppliers SET supplier_code=@code, name=@name, contact_name=@contact, phone=@phone, email=@email, address=@address, service_scope=@scope, vendor_type=@type, is_approved=@approved WHERE supplier_id=@id''',
                  params: {
                    'code': code.text.trim(),
                    'name': name.text.trim(),
                    'scope': scope.text.trim(),
                    'type': vendorType,
                    'contact': contact.text.trim(),
                    'phone': phone.text.trim(),
                    'email': email.text.trim(),
                    'address': address.text.trim(),
                    'approved': approved ? 1 : 0,
                    'id': vendor['supplier_id'],
                  },
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _load();
  }
}
