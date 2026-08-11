import sqlite3
import json
import re

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Get all machines for mapping
with open('machines.json', encoding='utf-8') as f:
    machines = json.load(f)

# Common mappings based on observation
machine_map = {
    'เครื่องพิมพ์ 6 สี': 'PT-03',
    'เครื่องพิมพ์ 2 สี': 'PT-01',  # Or PT-04 (Jumbo)
    'เครื่องพิมพ์ดิจิตอล 2': 'DP-01', # Or DP-02/03
    'ไดคัทออโต้': 'DC-01', # ไดคัท 1700 Auto
    'ปะกาวเซมิ': 'GM-01', # Or GM-02
    'ปะกาวเลเซอร์บ่อย': 'GM-06', # Assuming เลเซอร์ = Auto? Or GM-04?
    'ปะกาวเลเซอร์': 'GM-06',
    'สล็อตคอม': 'SC-01', # Or SC-02..04
    'ผ่าออโต้': 'SM-04', # เครื่องสับ/ผ่า Auto
    'เครื่องผ่าใบมีดเดี่ยว': 'SM-06', # เครื่องผ่าใบมีดเดี่ยว
    'ปะกาวเกี่ยวกัน': 'GM-04', # ปะกาวเกี่ยวกัน
    'มัดงานECF': 'BM-01',
    'เครื่องปะกาว2หัว': 'GM-03', # ปะกาว 2 หัว
    'เครื่องพิมพ์สีจัมโบ้': 'PT-04', # เครื่องพิมพ์ 2 สี Jumbo
    'สล็อตไส1้': 'SC-01', # SC = สล็อตคอม / สล็อตไส้ ?
    'สล็อตไส2้': 'SC-02',
    'พัดลม(ป้าวันดี)': None,
    'รถแฮนลิฟท์': None,
    'เครื่องมัดเชือกฟาง': 'BM-01',
    'เครื่องปะกาวลิ้นกล่อง': 'GM-07',
    'ติดบล็อก': None,
    'เครื่องสล็อตออโต้': 'SC-01',
    'ไดคัท1700': 'DC-03', # หรือ DC-01
    'ตอกเย็บลวด': 'ST-01',
    'ตอกเย็บลวด ST01': 'ST-01',
    'ตอกเย็บลวด1,2,3': 'ST-01'
}

# Resolve machine ID
def get_machine_id(title):
    for key, no in machine_map.items():
        if no and key in title:
            # Find ID
            for m in machines:
                if m['no'] == no:
                    return m['id'], m['name']
    
    # Fallback to general lookup
    for m in machines:
        if m['name'] in title or m['no'] in title:
            return m['id'], m['name']
            
    return None, None

def fix_date(date_str):
    if not date_str: return date_str
    # format: YYYY-MM-DD HH:MM:SS
    parts = date_str.split(' ')
    if len(parts) != 2: return date_str
    
    date_parts = parts[0].split('-')
    if len(date_parts) != 3: return date_str
    
    year = int(date_parts[0])
    if year > 2040:
        year -= 43
        
    return f"{year:04d}-{date_parts[1]}-{date_parts[2]} {parts[1]}"

# Get all legacy work orders
cur.execute("SELECT wo_no, title, created_at, completed_at FROM work_orders WHERE wo_no LIKE 'WO-2026-%'")
rows = cur.fetchall()

updated_count = 0

for row in rows:
    wo_no = row[0]
    title = row[1]
    created_at = row[2]
    completed_at = row[3]
    
    new_created = fix_date(created_at)
    new_completed = fix_date(completed_at)
    
    # Machine mapping
    m_id, m_name = get_machine_id(title)
    
    # If mapped, replace colloquial name with official name in title
    new_title = title
    if m_name:
        for key in machine_map.keys():
            if key in new_title:
                new_title = new_title.replace(key, f"{m_name}")
                break
    
    # Only update if there are changes
    if new_created != created_at or new_completed != completed_at or m_id or new_title != title:
        if m_id:
            cur.execute("""
                UPDATE work_orders
                SET created_at = ?, completed_at = ?, updated_at = ?, started_at = ?, machine_id = ?, title = ?
                WHERE wo_no = ?
            """, (new_created, new_completed, new_completed, new_created, m_id, new_title, wo_no))
        else:
            cur.execute("""
                UPDATE work_orders
                SET created_at = ?, completed_at = ?, updated_at = ?, started_at = ?
                WHERE wo_no = ?
            """, (new_created, new_completed, new_completed, new_created, wo_no))
        updated_count += 1

conn.commit()
conn.close()

print(f"Updated {updated_count} work orders successfully.")
