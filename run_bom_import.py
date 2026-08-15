
import sqlite3
import pandas as pd
import uuid

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

df = pd.read_excel(r'Y:\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\05-อะไหล่เครื่องจักร.xlsx', header=2)
df.columns = [str(col).strip() for col in df.columns]

# The column 'อะไหล่' is index 2. Let's use index to be safe against encoding issues in code
part_name_col = df.columns[2]
part_code_col = df.columns[3]
machine_name_col = df.columns[0]
machine_code_col = df.columns[1]

df = df.dropna(subset=[part_name_col])

c.execute('SELECT machine_id, machine_name FROM machines')
machine_map = {row[1].lower().replace(' ', ''): row[0] for row in c.fetchall()}
c.execute('SELECT machine_id, machine_no FROM machine_snapshots')
for row in c.fetchall():
    if row[1]: machine_map[row[1].lower().replace(' ', '')] = row[0]

c.execute('SELECT part_id, part_code FROM spare_parts')
parts_map = {row[1].upper(): row[0] for row in c.fetchall() if row[1]}

new_parts_count = 0
for idx, row in df.iterrows():
    part_name = str(row.get(part_name_col, '')).strip()
    part_code = str(row.get(part_code_col, '')).strip()
    if part_name == 'nan' or not part_name: continue
    if not part_code or part_code == 'nan': part_code = f'PART-{str(uuid.uuid4())[:8].upper()}'
    
    part_code_up = part_code.upper()
    if part_code_up not in parts_map:
        part_id = str(uuid.uuid4())
        safety_stock = 0
        try: safety_stock = int(row.get('Safety Stock', 0))
        except: pass
        category = str(row.get('ระบบ', 'Others')).strip()
        if category == 'nan': category = 'Others'
        
        c.execute('INSERT INTO spare_parts (part_id, part_code, part_name, category, reorder_level, is_active, created_at) VALUES (?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP)', (part_id, part_code, part_name, category, safety_stock))
        parts_map[part_code_up] = part_id
        new_parts_count += 1

print(f'Inserted {new_parts_count} new spare parts.')

c.execute('DELETE FROM part_machine_map')
current_machine_id = None
bom_count = 0

for idx, row in df.iterrows():
    m_name = str(row.get(machine_name_col, '')).strip()
    m_code = str(row.get(machine_code_col, '')).strip()
    
    if m_name and m_name != 'nan':
        match_id = None
        if m_code and m_code != 'nan':
            mc = m_code.lower().replace(' ', '')
            if mc in machine_map: match_id = machine_map[mc]
        if not match_id:
            mn = m_name.lower().replace(' ', '')
            for k, v in machine_map.items():
                if mn in k or k in mn:
                    match_id = v
                    break
        current_machine_id = match_id
            
    part_name = str(row.get(part_name_col, '')).strip()
    part_code = str(row.get(part_code_col, '')).strip()
    if part_name == 'nan' or not part_name: continue
    
    part_code_up = part_code.upper()
    if part_code_up in parts_map and current_machine_id:
        part_id = parts_map[part_code_up]
        map_id = str(uuid.uuid4())
        qty = 1
        try:
            qty_raw = str(row.get('จำนวนPart', '1'))
            if qty_raw != 'nan': qty = int(qty_raw)
        except: pass
        notes = str(row.get('รายละเอียด', '')).strip()
        if notes == 'nan': notes = ''
        try:
            c.execute('INSERT INTO part_machine_map (map_id, machine_id, part_id, quantity, notes) VALUES (?, ?, ?, ?, ?)', (map_id, current_machine_id, part_id, qty, notes))
        except:
            c.execute('UPDATE part_machine_map SET quantity = quantity + ? WHERE machine_id = ? AND part_id = ?', (qty, current_machine_id, part_id))
        bom_count += 1

conn.commit()
print(f'Inserted {bom_count} BOM mappings.')
