"""One-time migration: add responsible_person column to machines table."""
import sqlite3

conn = sqlite3.connect('masapp.db', timeout=3)
cols = [r[1] for r in conn.execute('PRAGMA table_info(machines)')]
print('Columns:', cols)
if 'responsible_person' not in cols:
    conn.execute('ALTER TABLE machines ADD COLUMN responsible_person VARCHAR(100)')
    conn.commit()
    print('SUCCESS: Column responsible_person added.')
else:
    print('Column already exists, nothing to do.')
conn.close()
