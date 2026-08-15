# -*- coding: utf-8 -*-
import sqlite3
import random
import uuid
from datetime import datetime, timedelta

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Get completed work orders
c.execute("SELECT wo_id, started_at, completed_at, actual_hours FROM work_orders WHERE status = 'completed'")
wos = c.fetchall()

# Get technicians
c.execute("SELECT user_id FROM users WHERE role IN ('technician', 'engineer')")
techs = [row[0] for row in c.fetchall()]
if not techs:
    techs = ['TECH-001', 'TECH-002', 'TECH-003']

# Get spare parts
c.execute("SELECT part_id FROM spare_parts")
parts = [row[0] for row in c.fetchall()]

labor_inserts = []
parts_inserts = []

for wo in wos:
    wo_id, started, completed, hours = wo
    if not hours or hours <= 0:
        hours = random.uniform(1.0, 4.0)
    
    # 1. Insert labor (1-2 records per wo)
    for _ in range(random.randint(1, 2)):
        labor_id = str(uuid.uuid4())
        tech = random.choice(techs)
        # Random hours split
        t_hours = hours / 2.0
        labor_inserts.append((
            labor_id, wo_id, tech, started, completed, t_hours, 'ซ่อมแซมและเปลี่ยนอะไหล่ตามอาการ', started
        ))

    # 2. Insert parts (1-3 records per wo, 70% chance)
    if parts and random.random() < 0.7:
        for _ in range(random.randint(1, 3)):
            wp_id = str(uuid.uuid4())
            part = random.choice(parts)
            qty = random.randint(1, 4)
            parts_inserts.append((
                wp_id, wo_id, part, qty, started
            ))

c.executemany('''
    INSERT INTO work_order_labor (labor_id, wo_id, technician_id, start_time, end_time, hours, task_description, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''', labor_inserts)

c.executemany('''
    INSERT INTO work_order_parts (wo_part_id, wo_id, part_id, quantity, created_at)
    VALUES (?, ?, ?, ?, ?)
''', parts_inserts)

conn.commit()
print(f"Inserted {len(labor_inserts)} labor records and {len(parts_inserts)} parts records.")
