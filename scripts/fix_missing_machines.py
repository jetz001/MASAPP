import sqlite3
import uuid
import datetime

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

def fetch_machine(no):
    cur.execute("SELECT * FROM machines WHERE machine_no = ?", (no,))
    m = cur.fetchone()
    if m:
        cols = [description[0] for description in cur.description]
        return dict(zip(cols, m))
    return None

def update_wo_machine(wo_no, machine_no):
    m = fetch_machine(machine_no)
    if not m:
        return False
    
    m_id = m['machine_id']
    
    # Check if snapshot exists
    cur.execute("SELECT snapshot_id FROM machine_snapshots WHERE machine_id = ? ORDER BY captured_at DESC LIMIT 1", (m_id,))
    snap = cur.fetchone()
    
    s_id = None
    if snap:
        s_id = snap[0]
    else:
        s_id = str(uuid.uuid4())
        now = datetime.datetime.now().isoformat()
        cur.execute('''
            INSERT INTO machine_snapshots (
                snapshot_id, machine_id, machine_no, machine_name, brand, model,
                dept_name, location, captured_at
            ) VALUES (?,?,?,?,?,?,?,?,?)
        ''', (
            s_id, m_id, m.get('machine_no'), m.get('machine_name'),
            m.get('brand'), m.get('model'), m.get('department'),
            m.get('location'), now
        ))
        
    cur.execute("UPDATE work_orders SET machine_id = ?, snapshot_id = ? WHERE wo_no = ?", (m_id, s_id, wo_no))
    return True

# Fix mappings
fixes = {
    'WO-2026-00263': 'GM-07',
    'WO-2026-00260': 'ST-03', # สล็อต/ตัด
    'WO-2026-00261': 'GM-02',
    'WO-2026-00262': 'GM-02',
    'WO-2026-00259': 'PT-04', # จัมโบ้
}

updated = 0
for wo, m_no in fixes.items():
    if update_wo_machine(wo, m_no):
        updated += 1

# Also scan ALL WOs and fix any other missing ones based on keywords
cur.execute("SELECT wo_no, title FROM work_orders WHERE snapshot_id IS NULL OR snapshot_id = ''")
wos = cur.fetchall()

keyword_map = {
    'ปะกาวGM07': 'GM-07',
    'ปะกาวGM02': 'GM-02',
    'ปะกาวGM01': 'GM-01',
    'ปะกาว GM01': 'GM-01',
    'สล็อตคอม': 'ST-03',
    'สล็อตไส้1': 'ST-01',
    'สล็อตไส้ 1': 'ST-01',
    'สล็อตไส้2': 'ST-02',
    'สล็อตไส้ 2': 'ST-02',
    'จัมโบ้': 'PT-04',
    'พิมพ์6สี': 'PT-03',
    'พิมพ์ 6 สี': 'PT-03',
    'พิมพ์2สี': 'PT-01',
    'พิมพ์ 2 สี': 'PT-01',
    'ไดคัทออโต้': 'DC-01',
    'ไดคัท 1700': 'DC-01',
    'ไดคัท DC02': 'DC-02',
    'ปะกาวเซมิ': 'GM-01',
    'ปะกาวออโต้': 'GM-06',
    'ปะกาวเกี่ยวกัน': 'GM-04',
    'ปะกาวเรซิบอย': 'GM-06',
    'ปะกาวเลเซอร์บ่อย': 'GM-06',
    'มัดเชือกฟาง BM02': 'BM-02',
    'มัดเชือกฟาง BM09': 'BM-09',
    'มัดเชือกฟาง': 'BM-01',
    'สับออโต้': 'SM-04',
    'ผ่าออโต้': 'SM-04',
    'ตอกเย็บลวด': 'SC-01',
    'แฮนลิฟท์': 'FG25S', # fallback
}

for wo in wos:
    wo_no, title = wo
    if wo_no in fixes: continue # already did
    
    for kw, m_no in keyword_map.items():
        if kw in title:
            if update_wo_machine(wo_no, m_no):
                updated += 1
            break

# Fix previous mistakes where I mapped slot machines to SC (เย็บลวด)
cur.execute("SELECT wo_no, title FROM work_orders WHERE machine_id IN (SELECT machine_id FROM machines WHERE machine_no IN ('SC-01', 'SC-02', 'SC-03'))")
wos_sc = cur.fetchall()
for wo in wos_sc:
    wo_no, title = wo
    if 'สล็อต' in title:
        m_no = 'ST-03'
        if 'ไส้1' in title or 'ไส้ 1' in title: m_no = 'ST-01'
        if 'ไส้2' in title or 'ไส้ 2' in title: m_no = 'ST-02'
        if update_wo_machine(wo_no, m_no):
            updated += 1

conn.commit()
conn.close()
print(f"Updated {updated} missing/wrong machine mappings.")
