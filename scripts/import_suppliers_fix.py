import sqlite3
import uuid
import datetime
import re

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

def categorize(name):
    name = name.lower()
    if any(k in name for k in ['อิงค์', 'หมึก', 'พิมพ์', 'พรนติ', 'print', 'flexo', 'เฟลก็ ซ', 'กราฟฟิก', 'ดีไซน์']):
        return 'หมึกพิมพ์และอุปกรณ์การพิมพ์'
    elif any(k in name for k in ['แมชชนี', 'จกัรกล', 'เซอรว์สิ', 'มอเตอร์', 'engineering', 'ซอ่ ม', 'บซิเินส']):
        return 'ซ่อมบำรุง/อะไหล่เครื่องจักร'
    elif any(k in name for k in ['ฮารด์แวร์', 'ฟิตติง', 'นิวเมตกิส์', 'เบลตงิ', 'belting', 'แบริง', 'อะไหล่', 'เซป็ เปอร์', 'motion', 'โมชนั ']):
        return 'อะไหล่/ชิ้นส่วน (Parts)'
    elif any(k in name for k in ['เคมี', 'โพลเิมอร์', 'chemical', 'polymer', 'เคมคิอล', 'กาว']):
        return 'สารเคมี (Chemicals)'
    elif any(k in name for k in ['พลาส', 'แพค', 'pack', 'บรรจุภณั ฑ์']):
        return 'พลาสติกและบรรจุภัณฑ์'
    elif any(k in name for k in ['กระดาษ', 'เปเปอร์', 'paper']):
        return 'กระดาษ (Paper)'
    else:
        return 'วัสดุสิ้นเปลือง/ทั่วไป'

with open('d:/DEV/MASAPP/scripts/suppliers_raw.txt', 'r', encoding='utf-8') as f:
    lines = [line.strip() for line in f.readlines() if line.strip()]

count = 0
for i in range(0, len(lines), 5):
    if i + 4 >= len(lines): break
    
    code = lines[i]
    short_name = lines[i+1]
    address = lines[i+2]
    contact_line = lines[i+3]
    full_name = lines[i+4]
    
    phone = ""
    email = ""
    fax = ""
    
    p_match = re.search(r'โทรศพั ท์\s+([0-9\-\(\)\s]+?)(?=(Email|Fax|$))', contact_line)
    if p_match: phone = p_match.group(1).strip()
    
    e_match = re.search(r'Email\s+([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})', contact_line)
    if e_match: email = e_match.group(1).strip()
    
    f_match = re.search(r'Fax\s+([0-9\-\(\)\s]+?)(?=(Email|โทรศพั ท์|$))', contact_line)
    if f_match: fax = f_match.group(1).strip()

    category = categorize(full_name + " " + short_name)
    
    # Check if already exists
    cur.execute("SELECT supplier_id FROM suppliers WHERE supplier_code = ?", (code,))
    if cur.fetchone():
        continue
        
    s_id = str(uuid.uuid4())
    now = datetime.datetime.now().isoformat()
    
    cur.execute('''
        INSERT INTO suppliers (
            supplier_id, supplier_code, name, contact_name, phone, email,
            address, is_approved, is_active, created_at, service_scope,
            vendor_type, is_outsource_vendor
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        s_id, code, full_name, short_name, phone, email,
        address, 1, 1, now, category, 'repair', 1
    ))
    count += 1

conn.commit()
conn.close()

print(f"Imported {count} suppliers successfully.")
