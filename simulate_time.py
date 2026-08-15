import sqlite3
import random
from datetime import datetime, timedelta

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("SELECT wo_id, created_at FROM work_orders WHERE status = 'completed'")
rows = c.fetchall()

updates = []
for wo_id, created_at in rows:
    if not created_at:
        continue
    try:
        # created_at might be in Iso8601 like 2023-03-01T08:00:00.000
        dt = datetime.fromisoformat(created_at.split('.')[0])
        
        # started_at = created_at + 10 to 60 mins
        start_dt = dt + timedelta(minutes=random.randint(10, 60))
        
        # completed_at = started_at + 30 mins to 6 hours
        comp_dt = start_dt + timedelta(minutes=random.randint(30, 360))
        
        actual_hrs = round((comp_dt - start_dt).total_seconds() / 3600.0, 2)
        
        updates.append((start_dt.isoformat() + '.000', comp_dt.isoformat() + '.000', actual_hrs, wo_id))
    except Exception as e:
        print('Error:', e)
        pass

c.executemany("UPDATE work_orders SET started_at = ?, completed_at = ?, actual_hours = ? WHERE wo_id = ?", updates)
conn.commit()
print(f'Updated {len(updates)} records with realistic repair times')
