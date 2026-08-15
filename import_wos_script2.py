import sqlite3
import uuid
import re
from datetime import datetime

db_path = r'\\No1\z\05-งานส่วนแผนก\03-MA-หน่วยงานซ่อมบำรุง(Maintenance)\Database\masapp.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('SELECT machine_id, machine_name FROM machines')
machine_map = {row[1].lower(): row[0] for row in c.fetchall()}

def parse_date(date_str):
    try:
        d, m, y = map(int, date_str.split('/'))
        if y < 100:
            if 66 <= y <= 75: y = y + 2500 - 543
            else: y = 2000 + y
        return f"{y:04d}-{m:02d}-{d:02d}T08:00:00.000"
    except:
        return None

def find_machine(text):
    for m in ['เครื่องพิมพ์ 6 สี', 'เครื่องพิมพ์ 2 สี', 'เครื่องพิมพ์สีจัมโบ้', 'ปะกาวเลซี่บอย', 'ปะกาวเกี่ยวกัน', 'ปะกาวเซมิ', 'ปะกาว2หัว', 'ปะกาวออโต้', 'ปะกาวGM07', 'ปะกาวGM02', 'ปะกาวGM01', 'ปะกาวสติกเกอร์', 'ปะกาวเรซิบอย', 'ไดคัทออโต้', 'ไดคัท1700', 'สล๊อตคอม', 'สล็อตไส้1', 'สล็อตไส้2', 'สล็อต/ตัด', 'สล็อตคอมพิวเตอร์', 'สับออโต้', 'ตอกเย็บลวด1,2,3', 'ตอกเย็บลวด ST01', 'ตอกเย็บลวด', 'ผ่าออโต้', 'ผ่าใบมีดเดี่ยว', 'ผ่าใบมีดคู่', 'มัดเชือกฟาง BM09', 'มัดเชือกฟาง BM02', 'มัดเชือกฟาง', 'มัดงานECF', 'รถแฮนลิฟท์ไฟฟ้า', 'รถแฮนลิฟท์', 'รถโฟลค์ลิฟท์ 1', 'แฮนลิฟท์ไฟฟ้า', 'หลังคา', 'โคมไฟ', 'พัดลม(ป้าวันดี)', 'พัดลม', 'รางท่อน้ำ', 'ไฟแสงสว่าง', 'ใบมีดเดียว', '2สีจัมโบ้', 'จัมโบ้', 'ปั๊มลมเติมอากาศ', 'ปั๊มลม', 'ปั๊มไดคัทออโต้']:
        if text.startswith(m):
            return m, text[len(m):].strip()
    # Fallback to the first word or two
    parts = text.split(' ')
    if len(parts) >= 2 and parts[1].isdigit() and parts[2] == 'สี':
        return ' '.join(parts[:3]), ' '.join(parts[3:])
    return parts[0], ' '.join(parts[1:])

lines = []
with open('import_wos.txt', 'r', encoding='utf8') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        # Format: Date Machine Problem Solution Responsible DateCompleted Notes/Category
        # Match Date
        match = re.match(r'^(\d{1,2}/\d{1,2}/\d{2})\s+(.*)$', line)
        if match:
            date_req_str, rest = match.groups()
            date_req = parse_date(date_req_str)
            
            machine, rest = find_machine(rest)
            
            # Now find Responsible and DateCompleted
            # Responsible usually starts with ช่าง, คุณ, พี่, โกโด้, บุญจันทร์, ฝ้าย, เจษ
            resp_match = re.search(r'\s(ช่าง\S+|คุณ\S+|พี่\S+|โกโด้|บุญจันทร์|ฝ้าย|เจษ)(?:\s|$)(.*)', rest)
            
            prob_sol = rest
            resp = 'ช่างบอล' # default
            date_comp = date_req
            category = ''
            
            if resp_match:
                prob_sol = rest[:resp_match.start()]
                resp = resp_match.group(1)
                tail = resp_match.group(2).strip()
                
                # tail might start with date
                d_match = re.match(r'^(\d{1,2}/\d{1,2}/\d{2})\s*(.*)$', tail)
                if d_match:
                    date_comp = parse_date(d_match.group(1))
                    category = d_match.group(2)
                else:
                    category = tail
            
            lines.append({
                'date': date_req,
                'machine': machine,
                'prob_sol': prob_sol.strip(),
                'resp': resp.strip(),
                'date_comp': date_comp,
                'category': category.strip()
            })
        else:
            # Maybe continuation line? Ignore for now as report looks mostly 1-line per record
            pass

# Clear old data
c.execute('DELETE FROM work_order_rca')
c.execute('DELETE FROM work_order_labor')
c.execute('DELETE FROM work_order_outsource')
c.execute('DELETE FROM work_order_parts')
c.execute('DELETE FROM work_orders')

c.execute('SELECT machine_id FROM machines LIMIT 1')
default_m_id = c.fetchone()[0]

wo_counter = 1
for row in lines:
    m_name = row['machine'].lower().replace(' ', '')
    m_id = default_m_id
    for k, v in machine_map.items():
        if m_name in k.replace(' ', '') or k.replace(' ', '') in m_name:
            m_id = v
            break
            
    wo_id = str(uuid.uuid4())
    wo_no = f"WO-{row['date'][:4]}-{wo_counter:04d}"
    wo_counter += 1
    
    prob = row['prob_sol']
    if len(prob) > 300: prob = prob[:300]
    
    c.execute('''INSERT INTO work_orders (
        wo_id, wo_no, machine_id, status, priority, title, description, 
        failure_symptom, assigned_to, started_at, completed_at, created_at, updated_at, closure_notes
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', (
        wo_id, wo_no, m_id, 'completed', 'normal', prob[:50] if prob else 'แจ้งซ่อม', prob, prob,
        'U003', row['date'], row['date_comp'], row['date'], row['date_comp'], prob
    ))
    
    c.execute('''INSERT INTO work_order_rca (
        rca_id, wo_id, root_cause, correction_action, cause_category, failure_type, analyzed_by, analyzed_at, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', (
        str(uuid.uuid4()), wo_id, prob, prob, 'เสื่อมสภาพตามอายุ (Normal Wear & Tear)', row['category'] if row['category'] else 'อื่นๆ (Others)', 'U003', row['date_comp'], row['date_comp'], row['date_comp']
    ))

conn.commit()
print(f"Inserted {len(lines)} records successfully!")
