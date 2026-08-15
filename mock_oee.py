# -*- coding: utf-8 -*-
import sqlite3
import random
import uuid
from datetime import datetime, timedelta

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Get some machines
c.execute("SELECT machine_id FROM machines WHERE is_active = 1 LIMIT 5")
machines = [row[0] for row in c.fetchall()]

if not machines:
    machines = ['MCH-001']

inserts = []
now = datetime.now()

# 30 days of data
for i in range(30):
    d = now - timedelta(days=i)
    # Give random data to 2 machines per day
    for m in random.sample(machines, min(2, len(machines))):
        record_id = str(uuid.uuid4())
        # typical 8 hour shift
        hrs = random.uniform(7.0, 8.0)
        target = 1000
        # actual close to target
        actual = int(target * random.uniform(0.8, 1.0))
        # good close to actual
        good = int(actual * random.uniform(0.9, 1.0))
        
        date_str = d.strftime('%Y-%m-%dT08:00:00.000')
        
        inserts.append((
            record_id, m, hrs, target, actual, good, date_str, 'manual'
        ))

# Delete old mock data if any
c.execute("DELETE FROM machine_running_hours WHERE data_source = 'manual'")

c.executemany('''
    INSERT INTO machine_running_hours (hours_id, machine_id, cumulative_hours, target_production, actual_production, good_production, recorded_date, data_source)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''', inserts)

conn.commit()
print(f"Inserted {len(inserts)} OEE records.")
