import sqlite3
db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT wo_no, created_at, machine_id, title FROM work_orders WHERE wo_no = 'WO-2026-00264'")
with open('debug_wo.txt', 'w', encoding='utf-8') as f:
    f.write(str(cur.fetchone()))
