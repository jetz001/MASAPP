import re

with open(r'd:\DEV\MASAPP\lib\features\spare_parts\spare_parts_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Instead of using exact garbled characters which can vary, use regex based on context
content = re.sub(r"title: Text\(widget\.isReceive \? '[^']*' : '[^']*'\),", r"title: Text(widget.isReceive ? 'รับของเข้าคลัง' : 'เบิกของออกจากคลัง'),", content)
content = re.sub(r"'\$\{widget\.part!\.partCode\} . \$\{widget\.part!\.partName\}',", r"'\${widget.part!.partCode} - \${widget.part!.partName}',", content)
content = re.sub(r"labelText: '[^']+',\n\s*suffixText: widget\.part\?\.partName != null \? '[^']*' : null\),", r"labelText: 'จำนวน',\n                  suffixText: widget.part?.partName != null ? 'ชิ้น' : null),", content)
content = re.sub(r"decoration: const InputDecoration\(\n\s*labelText: '[^']+'\),", r"decoration: const InputDecoration(\n                  labelText: 'อ้างอิง (เลขที่ใบงาน / PO)'),", content)
content = re.sub(r"decoration:\n\s*const InputDecoration\(labelText: '[^']+'\),", r"decoration:\n                  const InputDecoration(labelText: 'หมายเหตุ'),", content)
content = re.sub(r": Text\(widget\.isReceive \? '[^']*' : '[^']*'\),", r": Text(widget.isReceive ? 'ยืนยันรับของ' : 'ยืนยันเบิกของ'),", content)
content = re.sub(r"content: Text\('[^']*\$\{p\.partCode\}[^']*'\),", r"content: Text('คุณต้องการลบอะไหล่ \${p.partCode} ใช่หรือไม่?'),", content)
content = re.sub(r"title: Text\(widget\.part == null \? '[^']*' : '[^']*'\),", r"title: Text(widget.part == null ? 'เพิ่มอะไหล่ใหม่' : 'แก้ไขอะไหล่'),", content)
content = re.sub(r"child: Text\('[^']*', style: TextStyle\(color: AppColors\.error\)\),", r"child: Text('ไม่สามารถโหลดรูปภาพได้', style: TextStyle(color: AppColors.error)),", content)
content = re.sub(r"Text\('[^']*', style: AppTextStyles\.bodySmall\),", r"Text('คลิกเพื่อเพิ่มรูปภาพ', style: AppTextStyles.bodySmall),", content)
content = re.sub(r"label: const Text\('[^']*', style: TextStyle\(color: AppColors\.error\)\),", r"label: const Text('ลบรูปภาพ', style: TextStyle(color: AppColors.error)),", content)
content = re.sub(r"validator: \(v\) => v == null \|\| v\.isEmpty \? '[^']*' : null,", r"validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกข้อมูล' : null,", content)
content = re.sub(r"decoration: const InputDecoration\(labelText: '[^']+\(Part Name\) \*'\),", r"decoration: const InputDecoration(labelText: 'ชื่ออะไหล่ (Part Name) *'),", content)
content = re.sub(r"decoration: const InputDecoration\(labelText: '[^']+\(Category\)'\),", r"decoration: const InputDecoration(labelText: 'หมวดหมู่ (Category)'),", content)
content = re.sub(r"decoration: const InputDecoration\(labelText: '[^']+\(Unit Cost\)'\),", r"decoration: const InputDecoration(labelText: 'ราคาต่อหน่วย (Unit Cost)'),", content)
content = re.sub(r"decoration: const InputDecoration\(labelText: '[^']+\(Reorder Level\)'\),", r"decoration: const InputDecoration(labelText: 'จุดสั่งซื้อ (Reorder Level)'),", content)
content = re.sub(r"Text\('\?\?\?\?'\)", r"Text('ยกเลิก')", content)
content = re.sub(r"Text\(''\)", r"Text('บันทึก')", content)

# specific hardcoded replacements:
content = content.replace("Text('????')", "Text('ยกเลิก')")
content = content.replace("child: const Text('ѹ֡')", "child: const Text('บันทึก')")
content = content.replace("Text('¡ԡ')", "Text('ยกเลิก')")
content = content.replace("Text('ѹ֡')", "Text('บันทึก')")
content = content.replace("v.isEmpty ? 'سҡ͡'", "v.isEmpty ? 'กรุณากรอกข้อมูล'")
content = content.replace("v.isEmpty ? '????????????????'", "v.isEmpty ? 'กรุณากรอกข้อมูล'")
content = content.replace("v.isEmpty ? 'سҡ͡'", "v.isEmpty ? 'กรุณากรอกข้อมูล'")
content = content.replace("Text('¡ԡ')", "Text('ยกเลิก')")
content = content.replace("Text('ѹ֡')", "Text('บันทึก')")


with open(r'd:\DEV\MASAPP\lib\features\spare_parts\spare_parts_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('Replaced')
