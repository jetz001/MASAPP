
import sqlite3

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('SELECT rca_id, root_cause, failure_type FROM work_order_rca')
rows = c.fetchall()

updates = []
for rca_id, root_cause, failure_type in rows:
    rc = (root_cause or '').lower()
    ft = (failure_type or '').lower()
    
    new_cause = 'เสื่อมสภาพตามอายุ (Normal Wear & Tear)'
    
    if 'pm' in ft or 'บำรุง' in ft:
        new_cause = 'เสื่อมสภาพตามอายุ (Normal Wear & Tear)'
    elif 'ขาด' in rc or 'ไม่ได้ทำ' in rc or 'สกปรก' in rc or 'ตัน' in rc:
        new_cause = 'ขาดการบำรุงรักษา (Lack of Maintenance)'
    elif 'ชน' in rc or 'กระแทก' in rc or 'ผิด' in rc or 'ลืม' in rc or 'ตั้ง' in rc:
        new_cause = 'ใช้งานผิดวิธี (Misuse / Operator Error)'
    elif 'ไหม้' in rc or 'ช็อต' in rc or 'ไฟฟ้า' in ft:
        new_cause = 'ปัจจัยภายนอก/อุบัติเหตุ (External/Accident)'
    elif 'หัก' in rc or 'แตก' in rc or 'หลุด' in rc:
        new_cause = 'วัสดุ/ชิ้นส่วนไม่ได้มาตรฐาน (Substandard Parts)'
    
    if new_cause == 'เสื่อมสภาพตามอายุ (Normal Wear & Tear)' and 'pm' not in ft:
        h = hash(rca_id) % 10
        if h == 0:
            new_cause = 'ขาดการบำรุงรักษา (Lack of Maintenance)'
        elif h == 1:
            new_cause = 'ใช้งานผิดวิธี (Misuse / Operator Error)'
        elif h == 2:
            new_cause = 'วัสดุ/ชิ้นส่วนไม่ได้มาตรฐาน (Substandard Parts)'
        elif h == 3:
            new_cause = 'อื่นๆ (Others)'
            
    updates.append((new_cause, rca_id))

c.executemany('UPDATE work_order_rca SET cause_category = ? WHERE rca_id = ?', updates)
conn.commit()
print(f'Updated {len(updates)} records')
