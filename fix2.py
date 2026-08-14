with open(r'd:\DEV\MASAPP\lib\features\spare_parts\spare_parts_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Fix code based on line numbers
lines[660] = "                        content: Text('คุณต้องการลบอะไหล่ ${p.partCode} ใช่หรือไม่?'),\n"
lines[685] = "      title: Text(widget.isReceive ? 'รับของเข้าคลัง' : 'เบิกของออกจากคลัง'),\n"
lines[697] = "                  labelText: 'จำนวน',\n"
lines[698] = "                  suffixText: widget.part?.partName != null ? 'ชิ้น' : null),\n"
lines[703] = "                  labelText: 'อ้างอิง (เลขที่ใบงาน / PO)'),\n"
lines[708] = "                  const InputDecoration(labelText: 'หมายเหตุ'),\n"
lines[715] = "              : Text(widget.isReceive ? 'ยืนยันรับของ' : 'ยืนยันเบิกของ'),\n"

lines[888] = "      title: Text(widget.part == null ? 'เพิ่มอะไหล่ใหม่' : 'แก้ไขอะไหล่'),\n"
lines[913] = "                              child: Text('ไม่สามารถโหลดรูปภาพได้', style: TextStyle(color: AppColors.error)),\n"
lines[921] = "                              Text('คลิกเพื่อเพิ่มรูปภาพ', style: AppTextStyles.bodySmall),\n"
lines[931] = "                    label: const Text('ลบรูปภาพ', style: TextStyle(color: AppColors.error)),\n"

lines[936] = "                  controller: _codeCtrl,\n"
# Note line 937 is missing in the file, it was originally 
# controller: _codeCtrl
# validator: ...
# I will insert it.
lines[937] = "                  decoration: const InputDecoration(labelText: 'รหัสอะไหล่ (Part Code) *'),\n                  validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกข้อมูล' : null,\n"

lines[942] = "                  decoration: const InputDecoration(labelText: 'ชื่ออะไหล่ (Part Name) *'),\n"
lines[943] = "                  validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกข้อมูล' : null,\n"

lines[948] = "                  decoration: const InputDecoration(labelText: 'หมวดหมู่ (Category)'),\n"
lines[956] = "                        decoration: const InputDecoration(labelText: 'ราคาต่อหน่วย (Unit Cost)'),\n"
lines[964] = "                        decoration: const InputDecoration(labelText: 'จุดสั่งซื้อ (Reorder Level)'),\n"

lines[978] = "          child: const Text('ยกเลิก'),\n"
lines[982] = "          child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('บันทึก'),\n"

with open(r'd:\DEV\MASAPP\lib\features\spare_parts\spare_parts_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('Fixed by line number')
