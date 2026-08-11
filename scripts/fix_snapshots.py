import sqlite3
import uuid
import datetime

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("SELECT wo_no, machine_id, snapshot_id FROM work_orders WHERE machine_id IS NOT NULL AND machine_id != ''")
wos = cur.fetchall()

updated = 0
for wo in wos:
    wo_no, m_id, s_id = wo
    if not m_id: continue
    
    cur.execute("SELECT snapshot_id FROM machine_snapshots WHERE machine_id = ? ORDER BY captured_at DESC LIMIT 1", (m_id,))
    snap = cur.fetchone()
    
    new_s_id = None
    if snap:
        new_s_id = snap[0]
    else:
        cur.execute("SELECT * FROM machines WHERE machine_id = ?", (m_id,))
        m = cur.fetchone()
        if m:
            cols = [description[0] for description in cur.description]
            m_dict = dict(zip(cols, m))
            new_s_id = str(uuid.uuid4())
            now = datetime.datetime.now().isoformat()
            cur.execute('''
                INSERT INTO machine_snapshots (
                    snapshot_id, machine_id, machine_no, machine_name, brand, model,
                    dept_name, location, captured_at
                ) VALUES (?,?,?,?,?,?,?,?,?)
            ''', (
                new_s_id, m_dict.get('machine_id'), m_dict.get('machine_no'), m_dict.get('machine_name'),
                m_dict.get('brand'), m_dict.get('model'), m_dict.get('department'),
                m_dict.get('location'), now
            ))
    
    if new_s_id and new_s_id != s_id:
        cur.execute("UPDATE work_orders SET snapshot_id = ? WHERE wo_no = ?", (new_s_id, wo_no))
        updated += 1

conn.commit()
conn.close()
print(f"Updated {updated} work orders with snapshot_ids.")
