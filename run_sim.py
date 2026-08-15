import sqlite3
import random
from datetime import datetime, timedelta
db_path = r"\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("SELECT wo_id, created_at FROM work_orders WHERE status = 'completed'")
updates = []
for wo_id, created_at in c.fetchall():
    if not created_at: continue
    dt = datetime.fromisoformat(created_at.split(".")[0])
    start_dt = dt + timedelta(minutes=random.randint(10, 60))
    comp_dt = start_dt + timedelta(minutes=random.randint(30, 360))
    hrs = round((comp_dt - start_dt).total_seconds() / 3600.0, 2)
    updates.append((start_dt.isoformat() + ".000", comp_dt.isoformat() + ".000", hrs, wo_id))
c.executemany("UPDATE work_orders SET started_at = ?, completed_at = ?, actual_hours = ? WHERE wo_id = ?", updates)
conn.commit()
print("Updated records")
