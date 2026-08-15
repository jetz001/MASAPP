import sqlite3
import pandas as pd
import uuid

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

df = pd.read_excel(r'Y:\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\05-อะไหล่เครื่องจักร.xlsx', skiprows=2)
# The headers should be row 2 (0-indexed). So skip 2 rows, reading row 3 as header.
# Let's inspect the headers.
df = pd.read_excel(r'Y:\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\05-อะไหล่เครื่องจักร.xlsx', header=2)
print("Headers:", df.columns.tolist())

# We expect columns like: ['ชื่อเครื่อง', 'รหัสเครื่อง', 'อะไหล่', 'รหัสอะไหล่', 'จำนวนPart', 'Safety Stock', 'รายละเอียด', 'ระบบ', 'Supplier', 'หมายเหตุ']

# Let's clean column names
df.columns = [str(col).strip() for col in df.columns]

# Remove rows where อะไหล่ or รหัสอะไหล่ is null
df = df.dropna(subset=['อะไหล่'])

# Get machine mapping from DB
c.execute('SELECT machine_id, machine_name FROM machines')
machine_map = {row[1].lower().replace(' ', ''): row[0] for row in c.fetchall()}
# also map by 'รหัสเครื่อง' if exists
c.execute('SELECT machine_id, machine_no FROM machine_snapshots')
for row in c.fetchall():
    if row[1]: machine_map[row[1].lower().replace(' ', '')] = row[0]

# Pre-populate parts dict
c.execute('SELECT part_id, part_code FROM spare_parts')
parts_map = {row[1].upper(): row[0] for row in c.fetchall() if row[1]}

# Insert new parts
for idx, row in df.iterrows():
    part_name = str(row.get('อะไหล่', '')).strip()
    part_code = str(row.get('รหัสอะไหล่', '')).strip()
    if part_name == 'nan' or not part_name:
        continue
    
    if not part_code or part_code == 'nan':
        part_code = f"PART-{str(uuid.uuid4())[:8].upper()}"
        
    part_code_up = part_code.upper()
    
    if part_code_up not in parts_map:
        part_id = str(uuid.uuid4())
        safety_stock = 0
        try:
            safety_stock = int(row.get('Safety Stock', 0))
        except:
            pass
            
        category = str(row.get('ระบบ', 'Others')).strip()
        if category == 'nan': category = 'Others'
        
        c.execute('''INSERT INTO spare_parts (
            part_id, part_code, part_name, category, reorder_level, is_active, created_at
        ) VALUES (?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP)''', (
            part_id, part_code, part_name, category, safety_stock
        ))
        parts_map[part_code_up] = part_id

# Insert BOM map
c.execute('DELETE FROM part_machine_map') # Clear existing to avoid duplicates if they asked for full update

# First pass to find the current machine name block (because some rows might have empty machine name if they belong to previous)
current_machine_id = None

for idx, row in df.iterrows():
    m_name = str(row.get('ชื่อเครื่อง', '')).strip()
    m_code = str(row.get('รหัสเครื่อง', '')).strip()
    
    if m_name and m_name != 'nan':
        # Try to find
        match_id = None
        
        # Exact code match?
        if m_code and m_code != 'nan':
            mc = m_code.lower().replace(' ', '')
            if mc in machine_map:
                match_id = machine_map[mc]
                
        # Fuzzy name match
        if not match_id:
            mn = m_name.lower().replace(' ', '')
            for k, v in machine_map.items():
                if mn in k or k in mn:
                    match_id = v
                    break
                    
        if match_id:
            current_machine_id = match_id
        else:
            print(f"Machine not found: {m_name}")
            current_machine_id = None
            
    part_name = str(row.get('อะไหล่', '')).strip()
    part_code = str(row.get('รหัสอะไหล่', '')).strip()
    if part_name == 'nan' or not part_name:
        continue
        
    part_code_up = part_code.upper()
    if part_code_up in parts_map and current_machine_id:
        part_id = parts_map[part_code_up]
        map_id = str(uuid.uuid4())
        
        qty = 1
        try:
            qty_raw = str(row.get('จำนวนPart', '1'))
            if qty_raw != 'nan':
                qty = int(qty_raw)
        except:
            pass
            
        notes = str(row.get('รายละเอียด', '')).strip()
        if notes == 'nan': notes = ''
            
        c.execute('''INSERT INTO part_machine_map (
            map_id, machine_id, part_id, quantity, notes, created_at
        ) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)''', (
            map_id, current_machine_id, part_id, qty, notes
        ))

conn.commit()
print("Spare parts and BOM update completed.")
