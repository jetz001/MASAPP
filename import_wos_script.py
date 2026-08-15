import sqlite3
import uuid
import re
from datetime import datetime

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Get machines to map names to IDs
c.execute('SELECT machine_id, machine_name FROM machines')
machine_map = {row[1].lower(): row[0] for row in c.fetchall()}

# Get users to map names to IDs
c.execute('SELECT user_id, full_name, nickname FROM users')
user_map = {}
for row in c.fetchall():
    user_id, full_name, nickname = row
    if full_name: user_map[full_name.lower()] = user_id
    if nickname: user_map[nickname.lower()] = user_id
    # Also add variations
    if nickname:
        user_map[f'ช่าง{nickname}'.lower()] = user_id
        user_map[f'พี่{nickname}'.lower()] = user_id

# Let's see what users we have
print("User Map:", user_map)

# Helper to find machine ID by fuzzy name
def find_machine_id(name):
    name_lower = name.lower().replace(' ', '')
    for m_name, m_id in machine_map.items():
        if name_lower in m_name.replace(' ', '') or m_name.replace(' ', '') in name_lower:
            return m_id
    # some manual mappings based on common names
    if 'พิมพ์ 6 สี' in name or 'พิมพ์6สี' in name:
        return find_machine_id('เครื่องพิมพ์ 6 สี')
    if 'ไดคัท' in name:
        return find_machine_id('เครื่องไดคัท')
    return None

def find_user_id(name):
    if not name: return None
    name_lower = name.lower().strip()
    if name_lower in user_map:
        return user_map[name_lower]
    for u_name, u_id in user_map.items():
        if u_name in name_lower or name_lower in u_name:
            return u_id
    return None

# Parse dates
def parse_date(date_str, is_buddhist=True):
    if not date_str or date_str.strip() == '': return None
    try:
        # Some are like 24/2/66, some 27/2/23
        parts = date_str.split(' ')[0].split('/')
        if len(parts) == 3:
            d, m, y = int(parts[0]), int(parts[1]), int(parts[2])
            if y < 100:
                if y >= 66 and y <= 75: # Buddhist 2566 -> 2023
                    y = y + 2500 - 543
                else: # AD 23 -> 2023
                    y = 2000 + y
            return f"{y:04d}-{m:02d}-{d:02d}T08:00:00.000"
    except:
        pass
    return None

lines = []
with open('import_wos.txt', 'r', encoding='utf8') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        # Format: Date | Machine | Problem | Solution | Responsible | DateCompleted | Notes/Category
        # Since it's space separated and parts can contain spaces, we need some regex magic or splitting
        
        # We will split by 2 or more spaces, or tab if exists
        parts = re.split(r'\t| {2,}', line)
        if len(parts) < 4:
            # Try to parse manually by known date format at start
            # This is tricky because the OCR uses single spaces often
            match = re.match(r'^(\d{1,2}/\d{1,2}/\d{2})\s+(.*?)\s+(.*?)\s+(ช่าง\S+|คุณ\S+|พี่\S+)\s*(\d{1,2}/\d{1,2}/\d{2})?\s*(.*)$', line)
            if match:
                date_req, machine, prob_sol, resp, date_comp, category = match.groups()
                # Split prob_sol into prob and sol - impossible to know where it splits
                # We'll just put the whole thing in problem
                prob = prob_sol
                sol = ''
                parts = [date_req, machine, prob, sol, resp, date_comp, category]
            else:
                print("Cannot parse:", line)
                continue
                
        lines.append(parts)

print(f"Parsed {len(lines)} lines")

# CLEAR OLD DATA
c.execute('DELETE FROM work_order_rca')
c.execute('DELETE FROM work_order_labor')
c.execute('DELETE FROM work_order_outsource')
c.execute('DELETE FROM work_order_parts')
c.execute('DELETE FROM work_orders')

wo_counter = 1
for parts in lines:
    try:
        date_req = parts[0]
        machine = parts[1] if len(parts) > 1 else ''
        prob = parts[2] if len(parts) > 2 else ''
        sol = parts[3] if len(parts) > 3 else ''
        resp = parts[4] if len(parts) > 4 else ''
        date_comp = parts[5] if len(parts) > 5 else ''
        category = parts[6] if len(parts) > 6 else ''

        if not date_comp: date_comp = date_req # estimate
        
        m_id = find_machine_id(machine)
        if not m_id:
            # Try to get the first machine in the DB just to not fail, or skip
            c.execute('SELECT machine_id FROM machines LIMIT 1')
            m_id = c.fetchone()[0]

        u_id = find_user_id(resp) or 'U003' # Default to some user if not found
        
        dt_req = parse_date(date_req) or datetime.now().isoformat()
        dt_comp = parse_date(date_comp) or dt_req

        wo_id = str(uuid.uuid4())
        wo_no = f"WO-{dt_req[:4]}-{wo_counter:04d}"
        wo_counter += 1
        
        c.execute('''INSERT INTO work_orders (
            wo_id, wo_no, machine_id, status, priority, title, description, 
            failure_symptom, assigned_to, started_at, completed_at, created_at, updated_at, closure_notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', (
            wo_id, wo_no, m_id, 'completed', 'normal', prob[:50], prob, prob,
            u_id, dt_req, dt_comp, dt_req, dt_comp, sol
        ))
        
        rca_id = str(uuid.uuid4())
        c.execute('''INSERT INTO work_order_rca (
            rca_id, wo_id, root_cause, correction_action, failure_type, analyzed_by, analyzed_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''', (
            rca_id, wo_id, prob, sol, category, u_id, dt_comp, dt_comp
        ))
    except Exception as e:
        print("Error inserting row:", parts, e)

conn.commit()
print("Migration completed!")
