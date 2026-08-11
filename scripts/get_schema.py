import sqlite3

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("SELECT name, sql FROM sqlite_master WHERE type='table' AND name LIKE '%pm%';")
for row in cur.fetchall():
    print(f"Table: {row[0]}")
    print(row[1])
    print("-" * 40)

conn.close()
