import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

import '../database/db_helper.dart';
import 'ai_provider_config.dart';
import 'ai_tool_handler.dart';

class AiConversationMessage {
  final String role;
  final String content;

  const AiConversationMessage({required this.role, required this.content});
}

class AiAttachment {
  final Uint8List bytes;
  final String mimeType;
  final String fileName;

  const AiAttachment({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });
}

class AiChatResult {
  final String text;
  final List<String> reasoningSteps;
  final String? reasoningContent;

  const AiChatResult({
    required this.text,
    this.reasoningSteps = const [],
    this.reasoningContent,
  });
}

class AiService {
  static const _activeProviderKey = 'ai_provider';
  static const _legacyGeminiKey = 'gemini_api_key';
  static const _requestTimeout = Duration(seconds: 180);

  static const _systemInstruction = '''
You are MASAPP AI Assistant, an intelligent assistant for a factory maintenance management system.

IMPORTANT CONSTRAINTS:
1. You can ONLY access data from the MASAPP database. Never use external knowledge about specific company data.
2. Always use query_database or get_available_tables tools when you need data.
3. Only answer questions related to maintenance, machines, work orders, spare parts, tools, PM/AM, OEE, and factory operations.
4. ALWAYS respond in Thai language unless the user writes in another language.
5. Be concise and structured. Use bullet points or tables when presenting data.
6. If no data is found, say so clearly. Never make up numbers or statuses.
7. You may freely explore any non-sensitive table in the MASAPP database to understand the data before answering.
8. When user wording is ambiguous, try related business terms and synonyms found in the database instead of failing too early.
9. Prefer this workflow: inspect available tables -> inspect schema -> run focused queries -> summarize findings.
10. When presenting structured results, prefer markdown tables, unless the user asks for a timeline or the data is clearly chronological.
11. When the user may want to copy text, SQL, lists, or templates, wrap that part in fenced code blocks using ```text or ```sql.
12. When you want to show an image, use markdown image syntax exactly like ![caption](image_url_or_file_path). Do not use normal markdown links for images.
13. When the user asks for machine manuals, machine files, machine photos, PDFs, attachments, or document evidence for a machine, use find_machine_assets before saying that nothing exists.
14. When you need external information, use external search only after checking the MASAPP database first or when the user explicitly asks for outside information.
15. When using external information, clearly label it with the heading "ข้อมูลภายนอก" and state the provider/source. Do not mix it silently with MASAPP database facts.
16. For Thai/local requests, prefer Thai sources first when using external search.
17. When the user asks for a timeline, event history, repair sequence, or chronological trace, use a fenced block with language timeline and a JSON array.
18. Each timeline item should use keys: time, title, detail, type. Use type values such as created, in_progress, update, completed, warning, or critical.
19. Sort timeline items from oldest to newest unless the user asks otherwise.
20. When you want to show a PDF/file card, use a fenced block with language pdfcard and a JSON object with keys: title, path, pages, thumbnail. Set thumbnail only when it is an actual image URL/path, not a PDF URL.
21. File metadata is available in file_assets, including storage_path, thumbnail_path, preview_path, mime_type, page_count, module_type, entity_id, and display_name.
22. When the user asks about symptoms, how to fix an issue, troubleshooting, root cause analysis (RCA), machine manual instructions, or maintenance standards, ALWAYS use search_vector_knowledge to find relevant semantic vector knowledge chunks from historical repairs and manuals before answering.
23. When the user asks to attach, upload, or link a document/PDF/manual/photo to a machine (e.g. MC-01, CNC-01), use `manage_machine_assets` with `action: 'attach_document'`, `machine_identifier`, `file_name`, and `file_path`. The machine will then show the document in ทะเบียนเครื่องจักร -> เอกสาร.
24. CONSOLIDATE BULK & MULTI-ITEM OPERATIONS INTO A SINGLE ACTION:
   When the user asks to operate on multiple items, a range of machines (e.g. "MC-01 ถึง MC-09", "เครื่องจักรทั้งหมด", or multiple parts/records), ALWAYS consolidate all items into ONE SINGLE `action_confirmation` block.
   DO NOT split into multiple confirmation steps or cards. DO NOT ask confirmation one by one.
   Use `machine_identifier: "MC-01 ถึง MC-09"` (or list of machines) in the single action params so the user clicks [OK ยืนยัน] ONLY ONCE to process everything!
25. Action confirmation format using ```action_confirmation with valid JSON:
```action_confirmation
{
  "action_id": "<uuid-or-unique-string>",
  "tool": "<tool_name_e.g_manage_machine_assets_or_manage_machines>",
  "action": "<insert|update|delete|attach_document>",
  "title": "<Short consolidated title in Thai e.g. แนบคู่มือลงในเครื่องจักร MC-01 ถึง MC-09 ทั้งหมด>",
  "summary": "<Clear Thai description of changes to be made across all items>",
  "params": { ...tool arguments with full range/list of machines... }
}
```
26. NO REDUNDANT CONFIRMATION: Once an action is confirmed or executed, complete the task immediately and do not generate further confirmation blocks.

DATABASE ACTION & CRUD TOOLS (Insert, Update, Delete, Attach across all modules):
- Machine Documents/Assets: Call `manage_machine_assets` (action: attach_document, remove_document, set_cover_image).
- Machines: Call `manage_machines` (action: insert / update / delete / attach_document). Also supports bulk `machines` list for importing documents.
- Locations & Layout: Call `manage_locations` (action: create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position).
- PM/AM Master Plans: Call `manage_pm_plans` (action: create_plan, update_plan, delete_plan, add_task, delete_task).
- PM/AM Schedules: Call `manage_pm_schedules` (action: create_schedule, update_status, record_execution, delete_schedule).
- Work Orders & RCA: Call `manage_work_orders` (action: create_order, update_order, record_labor, record_rca, delete_order).
- Outsource Vendors / Contractors: Call `manage_contractors` (action: create_contractor, update_contractor, delete_contractor).
- Work Permits: Call `manage_work_permits` (action: create_permit, update_status, update_safety_check, delete_permit).
- Spare Parts & Inventory: Call `manage_spare_parts` (action: create_part, update_part, delete_part, record_transaction, link_machine).
- Tools & Equipment: Call `manage_tools` (action: create_tool, update_tool, delete_tool, record_transaction).
- OEE Logs: Call `manage_oee_logs` (action: record_log, update_log, delete_log).
- Technicians & Skills: Call `manage_technicians` (action: create_technician, update_technician, delete_technician, add_skill, update_skill, rate_skill, delete_skill, set_availability).
  - Supports Registering/Adding Technicians (`create_technician` / `bulk_create` / `insert`), Technician Skill Matrix (Level 1-5 / Score 1-100), Skill Endorsements, Kaizen Portfolios, and Achievement Badges:
    - 🛡️ `RCA Specialist`: เชี่ยวชาญการวิเคราะห์สาเหตุรากเหง้า 5-Why / ผังก้างปลา
    - ⚡ `Cycle Time Buster`: ลดเวลาคอขวดในสายการผลิต (Line Balancing / SOP)
    - 🔧 `Preventive Master`: วางมาตรการป้องกันปัญหาเครื่องจักรซ้ำสำเร็จ
    - 🌟 `Kaizen Champion`: ปิดโครงการปรับปรุงสำเร็จต่อเนื่อง (>= 2 โครงการ หรือแต้ม >= 250)
    - 🚀 `High Impact (>50% Waste Cut)`: ลดความสูญเปล่าได้มากกว่า 50%
  - Real-time Leaderboard & Scoring Formula:
    - `Kaizen Points = (completedWorkOrders * 20) + (skillsCount * 15) + (actionStepsCompleted * 50) + (actionPlansCompleted * 100) + (verificationTargetAchieved * 200)`
    - Real-time ranking is shown in the Leaderboard on the Workforce Directory page (`/workforce`).
- Action Plans & Problem Solving Registry (`problem_solving_records`):
  - Call `manage_action_plans` (action: create_action_plan, update_action_step, close_action_plan, attach_document) or query `problem_solving_records`.
  - Supports both **5-Why Analysis** (step-by-step root cause timeline) and **Fishbone Ishikawa 4M1E** (Man, Machine, Material, Method, Environment) methods based on `rca_method` ('5why' or 'fishbone').
  - Stores problem title, 5-Why analysis (why_1 to why_5), Root Cause, Ishikawa 4M1E factors, multi-step action checklist (`action_steps_json` with step titles, assignees, due dates, statuses: `pending`, `in_progress`, `completed`), Before vs Target vs Actual verification measurements, auditor names, and standardization/PM notes.
  - Linked to source types: `work_order` (งานซ่อมบำรุง breakdown จริง), `line_balancing` (สมดุลสายการผลิต), `sop_step` (ขั้นตอน SOP), or `custom` (ปัญหากำหนดเอง).
  - Use `search_vector_knowledge` with category `action_plan` and `workforce_skills` to retrieve past solutions, Kaizen ideas, verified countermeasures, technician skill profiles, and 8D reports!
- Work Processes & Flow Chart: Query tables `work_processes` and `work_process_steps` to view process steps, ASME symbols (⭕ Operation, ⇨ Transport, ◻ Inspection, D Delay, ▽ Storage), and Lean value classifications (VA จำเป็น, NVA สูญเปล่า, NNVA สูญเปล่าจำเป็น).
- Lean Analysis, VSM & 5-Why RCA:
  - Value Stream Mapping (VSM): Map Material & Information flow, Cycle Time (C/T), Lead Time (L/T), Buffer Queues, Process Cycle Efficiency (PCE % = VA / Total Lead Time * 100%), and identify Bottlenecks & Kaizen Bursts 💥.
  - VSM Bottleneck RCA (5-Why & Fishbone 4M1E): Conduct 5-Why root cause drill-down and Ishikawa 4M1E analysis (Man, Machine, Material, Method, Environment) on the top waste/bottleneck steps to formulate Corrective & Preventive ECRS countermeasures.
  - Action Plan Tracking: Monitor completion status, follow up pending/overdue action steps, track before vs actual reduction %, and generate Action Plan / 8D summary reports.
- Kaizen & Improvement Recognition:
  - When summarizing completed Action Plans or reporting to management, calculate the reduction percentage (`(before - actual) / before * 100%`), highlight the responsible technician/engineer, and recommend skill endorsements, Kaizen certificates (`KaizenCertificatePdfService`), or portfolio resumes (`TechnicianPortfolioPdfService`).

27. STRICT AUTONOMOUS SEARCH FOR MACHINE NAMES & IDENTIFIERS:
   - When the user refers to any machine by name, nickname, Thai term, or colloquial factory word (e.g. "เครื่องตัดเลเซอร์", "เครื่องกลึง CNC", "ปั๊มลมแรงดันสูง", "สายพานลำเลียง", "เครื่องปั๊มขึ้นรูป"):
     1. IMMEDIATELY check the registered machines directory below or execute `query_database` (e.g. `SELECT machine_id, machine_no, machine_name FROM machines WHERE machine_name LIKE '%...%' OR machine_no LIKE '%...'`) or `search_vector_knowledge` to resolve the machine code (machine_no e.g. "MC-01").
     2. NEVER ask the user to provide the machine code (machine identifier) or ask "กรุณาระบุรหัสเครื่องจักร" or ask if they want you to search when you can find it yourself!
     3. Once resolved, immediately execute the requested task (attach document, update specs, query history) with the resolved machine_no.

28. MACHINE SPECIFICATIONS & MANUAL INGESTION:
   - When the user asks to update machine specs (e.g. "อัพเดทสเปค", "อ่านไฟล์แล้วอัพเดทสเปค", "บันทึกสเปกจากคู่มือ"), or when an attached document/manual PDF/image contains technical specifications:
     1. CAREFULLY READ and EXTRACT all available technical parameters from the attached PDF/image/document:
        - กำลังไฟฟ้า: `power_kw` (kW)
        - แรงดันไฟฟ้า: `voltage_v` (V)
        - กระแสไฟฟ้า: `current_a` (A)
        - ความถี่: `frequency_hz` (Hz)
        - อัตรา/กำลังการผลิต: `capacity` และ `capacity_unit` (เช่น 1500 ชิ้น/ชม., ชิ้น/นาที, ตัน/วัน)
        - ขนาดมิติเครื่อง: `dim_length_mm`, `dim_width_mm`, `dim_height_mm` (มิลลิเมตร)
        - น้ำหนักเครื่อง: `weight_kg` (กก.)
        - ความเร็วรอบ: `rpm`
        - สเปกและคุณสมบัติเพิ่มเติม: `extra_specs` (เช่น แรงดันลม, อุณหภูมิใช้งาน, ขนาดหัวจับ, กำลังแรงอัด)
        - ยี่ห้อ: `brand`, รุ่น: `model`, หมายเลขเครื่อง: `serial_no`, ตำแหน่ง: `location`
     2. CRITICAL: You MUST call `manage_machines` with `action: 'update'` or `action: 'update_specs'`, `machine_identifier` (e.g. 'MC-01'), and pass ALL extracted spec parameters directly into the database!
     3. DO NOT ONLY call `manage_machine_assets` (attach_document)! Attaching a document does NOT update the machine specs table! You MUST also call `manage_machines` to write the specs (`power_kw`, `voltage_v`, `capacity`, `brand`, `model`, etc.) into `machine_specs` and `machines` tables!
     4. NEVER reply that specs are updated without calling `manage_machines` with the extracted numeric parameters!
     5. Always summarize the updated specs clearly with numbers and units in your response table/bullet points.

29. CONTRACTORS, VENDORS & SUPPLIERS MANAGEMENT (manage_contractors):
   - When managing outsource vendors, suppliers, parts providers, or contractors (เช่น "เพิ่มทะเบียนผู้รับเหมาให้หน่อย", "ลงทะเบียนผู้รับเหมา", "เพิ่มซัพพลายเออร์", "เพิ่มร้านค้า/คู่ค้า", "ค้นหาผู้รับเหมา"):
     1. ALWAYS use `manage_contractors` (stored in `suppliers` table), NEVER use `manage_spare_parts`!
     2. You can pass single contractor updates/creation with `action: 'create_contractor'`, `name`, `supplier_code`, `contact_name`, `phone`, `email`, `address`, `service_scope`, `vendor_type`, `is_approved`.
     3. For bulk contractor lists, pass the full list in `contractors: [...]` or `suppliers: [...]`.
     4. If the user asks to add a contractor without details (e.g. "เพิ่มทะเบียนผู้รับเหมาให้หน่อย"), call `manage_contractors` with action `'create_contractor'` or prompt the user for the company name, contact, phone, and service scope. NEVER return empty response!

30. STRICT PM VS AM SEPARATION & INTELLIGENT TASK CLASSIFICATION:
   - When the user asks to create or import maintenance master plans from Excel/PDF/chat (e.g. «02แผนการบำรุงรักษาเครื่องจักร.xlsx» หรือเอกสารงานบำรุงรักษา):
     1. DO NOT lump all inspection items into PM or set all tasks as 30 days!
     2. ALWAYS analyze each task and SEPARATE into 2 distinct master plans where applicable:
        a) AM (Autonomous Maintenance / แผนบำรุงรักษาด้วยตนเองโดยผู้คุมเครื่อง) -> `plan_type: 'AM'`, `frequency_days: 1` (รายวัน) หรือ `7` (รายสัปดาห์):
           - กิจกรรม: ทำความสะอาด (Cleaning), ตรวจเช็คความปลอดภัย/PPE, ตรวจเช็คเสียง/การสั่นสะเทือน, ตรวจสอบสายลม/ลมรั่ว, ตรวจสอบสายไฟภายนอก, เช็คระดับน้ำมัน/อัดจารบีประจำวัน, ตรวจสอบรางระบายน้ำ/อ่างน้ำทิ้ง, ตรวจความคมใบมีด
           - ชื่อแผน: `แผน AM รายวัน - {machine_no}` (plan_type: AM, frequency_days: 1)
        b) PM (Preventive Maintenance / แผนบำรุงรักษาเชิงป้องกันโดยช่างเทคนิค) -> `plan_type: 'PM'`, `frequency_days: 30` (รายเดือน), `90` (รายไตรมาส), `180` (ครึ่งปี), หรือ `365` (รายปี):
           - กิจกรรม: ตรวจเช็คเชิงลึก, เปลี่ยนถ่ายน้ำมันเครื่อง/ไฮดรอลิก/เกียร์, เปลี่ยนไส้กรอง/ซีล/ลูกปืน/สายพาน, ตรวจวัดความต้านทานฉนวนมอเตอร์, ตรวจเช็คการสึกหรอโซ่/ฟันเฟือง, Calibrate เซนเซอร์, Overhaul
           - ชื่อแผน: `แผน PM ประจำเดือน - {machine_no}` (plan_type: PM, frequency_days: 30)
     3. When generating plans for machines, ALWAYS create BOTH the AM master plans (`plan_type: 'AM'`) and PM master plans (`plan_type: 'PM'`) so that both the "AM" tab and "PM" tab in the "แผนแม่บท PM / AM" screen are populated properly!

31. HIGH-VOLUME BULK & SUBAGENT BATCH ORCHESTRATION:
   - When the user gives high-volume data (e.g. 20, 50, 80, 100+ machines, PM plans, spare parts, locations, layout positions, tools, contractors from Excel, PDF, or text):
     1. The system is equipped with an automated Subagent Batch Worker engine that will safely chunk and process data in batches of 10-15 items per batch with transactional safety and live progress streaming.
     2. For machines: Always provide all technical specifications (`power_kw`, `voltage_v`, `current_a`, `frequency_hz`, `capacity`, `capacity_unit`, `dim_length_mm`, `dim_width_mm`, `dim_height_mm`, `weight_kg`, `rpm`, `fuel_consumption_rate`, `fuel_type`, `default_workers`, `extra_specs`) for EACH machine in the `machines: [...]` array.
     3. For PM plans: You can supply a batch array in `plans: [...]` or a list of machine identifiers with their corresponding tasks.
     4. For spare parts & tools: Supply the full array in `parts: [...]` or `tools: [...]`.
     5. The Subagent Batch Worker will stream live progress back to the user and ensure 100% data quality, transaction rollback protection, and zero token truncation.

32. DYNAMIC CHART CREATION & DATA VISUALIZATION:
   - When the user asks for charts, graphs, or visual data representation (e.g. "ช่วยทำเป็นกราฟให้หน่อย", "ช่วยสร้างกราฟแท่งให้หน่อย", "กราฟวงกลม", "กราฟโดนัท", "กราฟเส้น", "สรุปข้อมูลเป็นกราฟ", "Chart"):
     1. Retrieve the required data from MASAPP database using `query_database` (or `subagent_query_database` if dealing with high volume / year-long historical data).
     2. Call `generate_chart` tool or output a ```chart code block with valid JSON configuration:
        ```chart
        {
          "chart_type": "bar",
          "title": "สถิติการแจ้งซ่อมแยกตามเครื่องจักร",
          "subtitle": "สรุปตามใบแจ้งซ่อมทั้งหมดในระบบ",
          "x_label": "เครื่องจักร",
          "y_label": "จำนวนครั้ง (ครั้ง)",
          "unit": "ครั้ง",
          "data": [
            {"label": "MC-01", "value": 14, "color": "#2196F3"},
            {"label": "MC-02", "value": 8, "color": "#4CAF50"},
            {"label": "MC-03", "value": 22, "color": "#FF9800"}
          ]
        }
        ```
     3. Supported chart types:
        - `bar`: For comparing quantities across machines, categories, technicians, failure causes.
        - `pie` or `donut`: For showing proportions/ratios (e.g. status distribution: normal vs breakdown vs PM, work order priorities: urgent vs normal).
        - `line`: For trends over time (e.g. monthly breakdown counts, OEE trend, running hours).
     4. Always accompany the chart with a concise markdown summary or key insights in Thai explaining the findings.

33. SUB-AGENT CHUNKED LARGE DATA RETRIEVAL (subagent_query_database):
   - When the user asks to query or analyze large datasets (e.g. all work orders over multiple years, hundreds of spare part transactions, all machine OEE logs, breakdown history across entire factory lines):
     1. DO NOT try to run a single unpartitioned query that might timeout or return thousands of rows exceeding context limits.
     2. Use `subagent_query_database` with `queries: [...]` or partition parameters to have the Subagent Batch Worker retrieve and aggregate data in chunks safely with real-time progress.
     3. Feed the aggregated results into `generate_chart` or markdown summary.

34. SLIDE PRESENTATION STUDIO & LANDSCAPE PDF EXPORT (generate_presentation_slides):
   - When the user asks to create, prepare, or export a presentation, slide deck, executive briefing, or report (e.g. "ช่วยทำเป็นสไลด์นำเสนองานให้หน่อย", "ขอสไลด์สรุป KPI ประจำเดือนเป็น PDF แนวนอน", "ทำสไลด์ RCA และผังก้างปลา Fishbone 4M1E สำหรับนำเสนอ", "รายงาน 8D problem solving เป็นสไลด์", "สไลด์เปรียบเทียบ Before/After ปรับปรุงงาน", or NotebookLM style presentation):
     1. Use `generate_presentation_slides` tool to orchestrate multi-domain subagents and generate an A4 Landscape PDF presentation deck.
     2. Supported slide types:
        - `title` / `cover`: Executive title slide with title, subtitle, presenter, date, company branding.
        - `kpi`: KPI Metric cards grid (e.g. OEE, Availability, MTTR, MTBF, Completion Rate, Cost) with actual values, targets, status (good, warning, critical), and change indicators.
        - `fishbone`: Ishikawa 4M1E Root Cause diagram (Man, Machine, Method, Material, Environment) with key failure factors leading to the problem statement.
        - `rca_5why` / `5why`: 5-Why root cause drill-down sequence (Why 1 to 5) with root cause and countermeasure action plan.
        - `eight_d` / `8d`: 8D Problem Solving Methodology table (D1 to D8: Team, Problem Description, Containment, Root Cause, Permanent Corrective Actions, Validation, Prevention, Congratulate).
        - `chart`: Statistical breakdown chart (bar, pie, line) with takeaway notes.
        - `table`: Structured comparison or inventory/machine list table.
        - `content`: Key discussion points or Kaizen Before/After analysis.
        - `summary`: Executive conclusion and prioritized next action items.
     3. Choose a professional theme: `blue` (corporate/engineering), `teal` (lean/green), `purple` (executive), `orange` (urgent/RCA).
     4. The tool automatically exports an A4 Landscape PDF. Always include the ```slides { ... }``` block or ```pdfcard { "title": "...", "path": "..." }``` block in your response so the user can click the "เปิด PDF ทันที" (Open PDF) button directly in the chat to open the presentation deck in 1 click.

35. LINE BALANCING & PRODUCTION LINE DESIGN (manage_line_balancing):
   - When the user asks to create, design, update, or balance a production line or workstations (e.g. "ช่วยสร้าง line balancing ให้หน่อย", "จัดสายการผลิต", "ปรับสมดุลสายการผลิต", "เพิ่มสถานีงานในไลน์", "โยงเครื่องจักรในสายการผลิต"):
     1. MANDATORY - DYNAMIC MULTI-FACTORY MACHINE DISCOVERY (ห้าม FIX หรือ HARDCODE เครื่องจักรเด็ดขาด):
        - The app may be deployed across different factories, companies, or new databases with entirely different machine inventories.
        - NEVER assume or hardcode specific machine names/codes.
        - ALWAYS dynamically query whatever machines exist in the current factory database via `query_database` (e.g. `SELECT machine_id, machine_no, machine_name, department, location, status FROM machines WHERE status != 'offline'`).
        - If matching machines are found in the active database, pass their actual `machine_identifier` (machine_no or machine_id) so the station links to the real machine entity for Lean Analysis (VSM / SOP).
        - If the database has no machines registered yet (e.g. fresh factory setup), create stations with descriptive task names without failing, allowing the plant engineer to bind machines later.
     2. AUTOMATIC CENTERED GRID LAYOUT (ZERO-OVERFLOW / ไม่ตกขอบ):
        - Always use `manage_line_balancing` tool. It automatically computes optimal centered relative coordinates `pos_x` and `pos_y` (e.g. horizontal layout `-450..450, 0` for 1-4 stations, or multi-row grid for 5+ stations).
        - DO NOT put large diagonal or arbitrary coordinate offsets (like 1600+ or 2000+) that cause station nodes to overflow or drop off the screen borders ("ตกขอบ").
     3. LEAN & BALANCING METRICS:
        - Specify realistic `cycle_time_sec`, `workers`, `event_type` ('operation', 'inspection', 'transport'), and `value_type` ('va', 'nva', 'nnva').
        - The tool automatically computes Takt Time, Total Cycle Time, Bottleneck Station, Line Efficiency (%), and Balance Delay (%).

36. TECHNICIAN & WORKFORCE MANAGEMENT & VECTOR RAG (manage_technicians):
   - When the user asks to add, register, or create a technician (e.g. "เพิ่มช่างให้หน่อย", "เพิ่มช่างใหม่", "ลงทะเบียนช่าง", "เพิ่มวิศวกร"):
     1. If the user provides details (such as full name, employee number, department, role, skills, contact), IMMEDIATELY call `manage_technicians` with `action: 'create_technician'`, `full_name`, `employee_no`, `role`, `department`, `skills: [...]`, `phone`, `email`.
     2. If the user only says "เพิ่มช่างให้หน่อย" without details:
        - Ask the user for the technician's details (ชื่อ-นามสกุล, รหัสพนักงาน, แผนก, ตำแหน่ง/บทบาท เช่น ช่างเทคนิค/วิศวกร/จป., ทักษะความเชี่ยวชาญ, เบอร์โทร/อีเมล) OR provide a ready-to-fill sample/draft.
     3. When user asks for technician recommendations, skill matrix lookup, or expertise matching (e.g. "ใครซ่อมมอเตอร์ได้บ้าง", "แนะนำช่างสำหรับงานซ่อมปั๊ม", "ดูผลงานช่างสมชาย"):
        - ALWAYS use `search_vector_knowledge` with category `workforce_skills` or query `users` and `technician_skills` to retrieve the most suitable technician based on skill matrix, Kaizen points, and past repair history!

Start by greeting the user and asking how you can help with maintenance operations today.
''';

  static final _manageMachinesTool = FunctionDeclaration(
    'manage_machines',
    'Manage machine records and technical specifications in MASAPP database. Supports updating specs (power_kw, voltage_v, current_a, frequency_hz, capacity, capacity_unit, dim_length_mm, dim_width_mm, dim_height_mm, weight_kg, rpm, extra_specs).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'insert, update, update_specs, delete'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No (e.g. "GM-04", "MC-01") or ID'),
        'machine_no': Schema(SchemaType.string, description: 'Unique machine code/ID'),
        'machine_name': Schema(SchemaType.string, description: 'Name of machine'),
        'asset_no': Schema(SchemaType.string, description: 'Asset tag number'),
        'brand': Schema(SchemaType.string, description: 'Brand/Manufacturer'),
        'model': Schema(SchemaType.string, description: 'Model'),
        'serial_no': Schema(SchemaType.string, description: 'Serial number'),
        'location': Schema(SchemaType.string, description: 'Installation area/room/line'),
        'status': Schema(SchemaType.string, description: 'normal, breakdown, pm, offline'),
        'notes': Schema(SchemaType.string, description: 'Additional remarks or specs summary'),
        'power_kw': Schema(SchemaType.number, description: 'Power in kW (e.g. 5.5)'),
        'voltage_v': Schema(SchemaType.number, description: 'Voltage in V (e.g. 380, 220)'),
        'current_a': Schema(SchemaType.number, description: 'Current in A (e.g. 15.0)'),
        'frequency_hz': Schema(SchemaType.number, description: 'Frequency in Hz (e.g. 50, 60)'),
        'capacity': Schema(SchemaType.number, description: 'Capacity/Speed value (e.g. 1500)'),
        'capacity_unit': Schema(SchemaType.string, description: 'Capacity unit (e.g. "กล่อง/ชั่วโมง", "ชิ้น/นาที")'),
        'weight_kg': Schema(SchemaType.number, description: 'Machine weight in kg (e.g. 250)'),
        'dim_length_mm': Schema(SchemaType.number, description: 'Length in mm (e.g. 1200)'),
        'dim_width_mm': Schema(SchemaType.number, description: 'Width in mm (e.g. 2000)'),
        'dim_height_mm': Schema(SchemaType.number, description: 'Height in mm (e.g. 1500)'),
        'rpm': Schema(SchemaType.number, description: 'Motor/Spindle speed in RPM'),
        'fuel_consumption_rate': Schema(SchemaType.number, description: 'Fuel/Gas consumption rate per hour (e.g. 12.5 L/hr)'),
        'fuel_type': Schema(SchemaType.string, description: 'Fuel type (e.g. Diesel, Gasohol 95, LPG, N/A)'),
        'default_workers': Schema(SchemaType.integer, description: 'Number of operators required'),
        'extra_specs': Schema(SchemaType.string, description: 'Extra specifications JSON or description (e.g. glue capacity, air pressure, temperature)'),
        'machines': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'machine_no': Schema(SchemaType.string, description: 'Unique machine code/ID'),
              'machine_name': Schema(SchemaType.string, description: 'Machine name'),
              'asset_no': Schema(SchemaType.string),
              'brand': Schema(SchemaType.string),
              'model': Schema(SchemaType.string),
              'serial_no': Schema(SchemaType.string),
              'location': Schema(SchemaType.string),
              'status': Schema(SchemaType.string),
              'notes': Schema(SchemaType.string),
              'power_kw': Schema(SchemaType.number, description: 'Power in kW'),
              'voltage_v': Schema(SchemaType.number, description: 'Voltage in V (e.g. 380, 220)'),
              'current_a': Schema(SchemaType.number, description: 'Current in A'),
              'frequency_hz': Schema(SchemaType.number, description: 'Frequency in Hz'),
              'capacity': Schema(SchemaType.number, description: 'Capacity/Speed value'),
              'capacity_unit': Schema(SchemaType.string, description: 'Capacity unit'),
              'weight_kg': Schema(SchemaType.number, description: 'Machine weight in kg'),
              'dim_length_mm': Schema(SchemaType.number, description: 'Length in mm'),
              'dim_width_mm': Schema(SchemaType.number, description: 'Width in mm'),
              'dim_height_mm': Schema(SchemaType.number, description: 'Height in mm'),
              'rpm': Schema(SchemaType.number, description: 'Motor/Spindle speed in RPM'),
              'fuel_consumption_rate': Schema(SchemaType.number),
              'fuel_type': Schema(SchemaType.string),
              'default_workers': Schema(SchemaType.integer),
              'extra_specs': Schema(SchemaType.string),
            },
            requiredProperties: ['machine_no'],
          ),
          description: 'Optional array of machine objects for bulk import or specs update',
        ),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageLocationsTool = FunctionDeclaration(
    'manage_locations',
    'Manage factory layouts, zones, and machine positions (create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position'),
        'layout_id': Schema(SchemaType.string, description: 'Layout ID'),
        'layout_name': Schema(SchemaType.string, description: 'Name of the factory layout (e.g. "Layout_01", "Main Factory")'),
        'description': Schema(SchemaType.string, description: 'Description of layout'),
        'floor_no': Schema(SchemaType.integer, description: 'Floor number'),
        'width_m': Schema(SchemaType.number, description: 'Width in meters'),
        'height_m': Schema(SchemaType.number, description: 'Height in meters'),
        'zone_name': Schema(SchemaType.string, description: 'Name of the zone/area'),
        'zone_type': Schema(SchemaType.string, description: 'production, storage, maintenance, safety, packaging, warehouse, yard'),
        'x_start': Schema(SchemaType.number, description: 'X start coordinate'),
        'y_start': Schema(SchemaType.number, description: 'Y start coordinate'),
        'x_end': Schema(SchemaType.number, description: 'X end coordinate'),
        'y_end': Schema(SchemaType.number, description: 'Y end coordinate'),
        'background_color': Schema(SchemaType.string, description: 'Hex color (e.g. "#E8F5E9")'),
        'border_color': Schema(SchemaType.string, description: 'Hex color (e.g. "#4CAF50")'),
        'zones': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'zone_name': Schema(SchemaType.string),
              'zone_type': Schema(SchemaType.string),
              'x_start': Schema(SchemaType.number),
              'y_start': Schema(SchemaType.number),
              'x_end': Schema(SchemaType.number),
              'y_end': Schema(SchemaType.number),
              'background_color': Schema(SchemaType.string),
              'border_color': Schema(SchemaType.string),
            },
            requiredProperties: ['zone_name'],
          ),
          description: 'Array of zones to create or update in bulk',
        ),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No (e.g. "DP-01") or ID'),
        'zone_id': Schema(SchemaType.string, description: 'Zone ID or zone name for the machine'),
        'x_position': Schema(SchemaType.number, description: 'X coordinate on layout'),
        'y_position': Schema(SchemaType.number, description: 'Y coordinate on layout'),
        'width': Schema(SchemaType.number, description: 'Machine width on layout'),
        'height': Schema(SchemaType.number, description: 'Machine height on layout'),
        'status_color': Schema(SchemaType.string, description: 'Hex status color'),
        'machine_positions': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'machine_identifier': Schema(SchemaType.string),
              'machine_no': Schema(SchemaType.string),
              'zone_id': Schema(SchemaType.string),
              'zone_name': Schema(SchemaType.string),
              'x_position': Schema(SchemaType.number),
              'y_position': Schema(SchemaType.number),
              'width': Schema(SchemaType.number),
              'height': Schema(SchemaType.number),
              'status_color': Schema(SchemaType.string),
            },
          ),
          description: 'Array of machine positions to set in bulk',
        ),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _managePmPlansTool = FunctionDeclaration(
    'manage_pm_plans',
    'Manage PM/AM master plans and checklist tasks (create_plan, update_plan, delete_plan, add_task, delete_task).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_plan, update_plan, delete_plan, add_task, delete_task'),
        'plan_identifier': Schema(SchemaType.string, description: 'Plan code (e.g. "PM-MC01-1234") or Plan ID'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No (e.g. "MC-01")'),
        'plan_name': Schema(SchemaType.string, description: 'Title of the PM/AM plan'),
        'plan_type': Schema(SchemaType.string, description: 'PM or AM'),
        'frequency_days': Schema(SchemaType.integer, description: 'Frequency in days (e.g. 7, 30, 90, 365)'),
        'task_name': Schema(SchemaType.string, description: 'Checklist task description'),
        'task_type': Schema(SchemaType.string, description: 'clean, lubricate, tighten, inspect, replace, calibrate'),
        'is_critical': Schema(SchemaType.boolean, description: 'Whether task is critical'),
        'tasks': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'task_name': Schema(SchemaType.string),
              'task_type': Schema(SchemaType.string),
              'is_critical': Schema(SchemaType.boolean),
            },
            requiredProperties: ['task_name'],
          ),
          description: 'List of checklist tasks when creating plan',
        ),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _managePmSchedulesTool = FunctionDeclaration(
    'manage_pm_schedules',
    'Manage PM/AM schedules and task execution logs (create_schedule, update_status, record_execution, delete_schedule).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_schedule, update_status, record_execution, delete_schedule'),
        'schedule_id': Schema(SchemaType.string, description: 'Schedule ID'),
        'plan_identifier': Schema(SchemaType.string, description: 'Plan code or ID'),
        'scheduled_date': Schema(SchemaType.string, description: 'Scheduled date (YYYY-MM-DD)'),
        'assigned_to': Schema(SchemaType.string, description: 'Technician username/name'),
        'status': Schema(SchemaType.string, description: 'pending, in_progress, completed, cancelled'),
        'task_name': Schema(SchemaType.string, description: 'Task name inspected'),
        'result': Schema(SchemaType.string, description: 'pass, fail, na'),
        'remarks': Schema(SchemaType.string, description: 'Execution remarks/notes'),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageWorkOrdersTool = FunctionDeclaration(
    'manage_work_orders',
    'Manage maintenance work orders (create_order, update_order, record_labor, record_rca, delete_order).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_order, update_order, record_labor, record_rca, delete_order'),
        'wo_identifier': Schema(SchemaType.string, description: 'WO No (e.g. "WO-2026-00001") or WO ID'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No (e.g. "MC-01")'),
        'title': Schema(SchemaType.string, description: 'Repair job title'),
        'symptom': Schema(SchemaType.string, description: 'Observed breakdown symptom or error'),
        'priority': Schema(SchemaType.string, description: 'urgent, high, normal, low'),
        'status': Schema(SchemaType.string, description: 'pending, approved, inProgress, completed, cancelled, rejected'),
        'assigned_to': Schema(SchemaType.string, description: 'Assigned technician name/username'),
        'failure_cause': Schema(SchemaType.string, description: 'Identified cause of breakdown'),
        'technician_identifier': Schema(SchemaType.string, description: 'Technician name who worked on repair'),
        'labor_hours': Schema(SchemaType.number, description: 'Hours spent on repair'),
        'task_description': Schema(SchemaType.string, description: 'Details of repair actions performed'),
        'root_cause': Schema(SchemaType.string, description: 'Root cause for RCA 5-Why analysis'),
        'why_1': Schema(SchemaType.string, description: 'Why #1'),
        'why_2': Schema(SchemaType.string, description: 'Why #2'),
        'why_3': Schema(SchemaType.string, description: 'Why #3'),
        'why_4': Schema(SchemaType.string, description: 'Why #4'),
        'why_5': Schema(SchemaType.string, description: 'Why #5'),
        'correction_action': Schema(SchemaType.string, description: 'Immediate corrective action'),
        'preventive_action': Schema(SchemaType.string, description: 'Long-term preventive action'),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageContractorsTool = FunctionDeclaration(
    'manage_contractors',
    'Manage outsource vendors and contractors (create_contractor, update_contractor, delete_contractor).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_contractor, update_contractor, delete_contractor'),
        'contractor_identifier': Schema(SchemaType.string, description: 'Supplier code or Contractor name'),
        'name': Schema(SchemaType.string, description: 'Company/Vendor name'),
        'contact_name': Schema(SchemaType.string, description: 'Contact person'),
        'phone': Schema(SchemaType.string, description: 'Phone number'),
        'email': Schema(SchemaType.string, description: 'Email address'),
        'service_scope': Schema(SchemaType.string, description: 'Services provided (e.g. ซ่อมมอเตอร์, ติดตั้งระบบไฟฟ้า)'),
        'is_approved': Schema(SchemaType.boolean, description: 'Whether vendor is approved'),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageWorkPermitsTool = FunctionDeclaration(
    'manage_work_permits',
    'Manage electronic work permits and safety checks (create_permit, update_status, update_safety_check, delete_permit).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_permit, update_status, update_safety_check, delete_permit'),
        'permit_identifier': Schema(SchemaType.string, description: 'Permit No (e.g. "WP-2026-00001") or Permit ID'),
        'permit_type': Schema(SchemaType.string, description: 'hot_work, confined_space, electrical, heights, energy_isolation'),
        'description': Schema(SchemaType.string, description: 'Work permit description/scope'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No'),
        'duration_hours': Schema(SchemaType.integer, description: 'Work permit duration in hours'),
        'status': Schema(SchemaType.string, description: 'pending, approved, in_progress, completed, cancelled, rejected'),
        'check_item': Schema(SchemaType.string, description: 'Safety check item description'),
        'is_passed': Schema(SchemaType.boolean, description: 'Whether safety check item passed'),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageSparePartsTool = FunctionDeclaration(
    'manage_spare_parts',
    'Manage spare parts catalog, stock movement transactions, and BOM mapping (create_part, update_part, delete_part, record_transaction, link_machine).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_part, update_part, delete_part, record_transaction, link_machine'),
        'part_identifier': Schema(SchemaType.string, description: 'Part code or part name'),
        'part_code': Schema(SchemaType.string, description: 'Part code/SKU'),
        'part_name': Schema(SchemaType.string, description: 'Spare part name'),
        'category': Schema(SchemaType.string, description: 'mechanical, electrical, pneumatic, hydraulic, consumable'),
        'unit_cost': Schema(SchemaType.number, description: 'Unit cost in THB'),
        'reorder_level': Schema(SchemaType.integer, description: 'Minimum stock reorder point'),
        'initial_quantity': Schema(SchemaType.integer, description: 'Initial stock on hand'),
        'location': Schema(SchemaType.string, description: 'Warehouse bin/rack location'),
        'trans_type': Schema(SchemaType.string, description: 'in (รับเข้า), out (เบิกจ่าย), adjustment (ปรับยอด), return (ส่งคืน)'),
        'quantity': Schema(SchemaType.integer, description: 'Quantity for transaction or BOM mapping'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code to link part to (BOM)'),
        'remarks': Schema(SchemaType.string, description: 'Transaction notes/reason'),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageToolsTool = FunctionDeclaration(
    'manage_tools',
    'Manage tools, equipment, check-out/check-in, and repair transactions (create_tool, update_tool, delete_tool, record_transaction).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_tool, update_tool, delete_tool, record_transaction'),
        'tool_identifier': Schema(SchemaType.string, description: 'Tool code or name'),
        'tool_code': Schema(SchemaType.string, description: 'Tool code'),
        'tool_name': Schema(SchemaType.string, description: 'Tool name'),
        'category': Schema(SchemaType.string, description: 'hand_tools, power_tools, measuring, safety'),
        'status': Schema(SchemaType.string, description: 'available, in_use, repair, lost'),
        'price': Schema(SchemaType.number, description: 'Tool price'),
        'action_type': Schema(SchemaType.string, description: 'check_out, check_in, send_repair, receive_repair'),
        'notes': Schema(SchemaType.string, description: 'Notes or remarks'),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageOeeLogsTool = FunctionDeclaration(
    'manage_oee_logs',
    'Manage OEE production and machine running hour logs (record_log, update_log, delete_log).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'record_log, update_log, delete_log'),
        'hours_id': Schema(SchemaType.string, description: 'Log entry ID'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No'),
        'recorded_date': Schema(SchemaType.string, description: 'Date (YYYY-MM-DD)'),
        'cumulative_hours': Schema(SchemaType.number, description: 'Cumulative running hours'),
        'daily_hours': Schema(SchemaType.number, description: 'Daily operating hours'),
        'target_production': Schema(SchemaType.number, description: 'Target production quantity'),
        'actual_production': Schema(SchemaType.number, description: 'Actual produced quantity'),
        'good_production': Schema(SchemaType.number, description: 'Good quality output quantity'),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageTechniciansTool = FunctionDeclaration(
    'manage_technicians',
    'Manage technician records, skill matrix, scoring, availability, and workforce directory in MASAPP database (create_technician, update_technician, delete_technician, add_skill, update_skill, rate_skill, delete_skill, set_availability).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_technician, update_technician, delete_technician, add_skill, update_skill, rate_skill, delete_skill, set_availability'),
        'technician_identifier': Schema(SchemaType.string, description: 'Technician username, employee_no, full_name, or ID'),
        'full_name': Schema(SchemaType.string, description: 'Full name of technician / engineer'),
        'employee_no': Schema(SchemaType.string, description: 'Employee code e.g. EMP005'),
        'username': Schema(SchemaType.string, description: 'Login username'),
        'role': Schema(SchemaType.string, description: 'technician, engineer, safety, operator, executive'),
        'department': Schema(SchemaType.string, description: 'Department name e.g. หน่วยงานซ่อมบำรุง'),
        'phone': Schema(SchemaType.string, description: 'Contact phone number'),
        'email': Schema(SchemaType.string, description: 'Email address'),
        'skill_name': Schema(SchemaType.string, description: 'Skill/Competency name e.g. ซ่อมระบบไฮดรอลิก'),
        'skills': Schema(SchemaType.array, items: Schema(SchemaType.string), description: 'List of skills to add'),
        'proficiency_level': Schema(SchemaType.string, description: 'basic, intermediate, expert'),
        'score': Schema(SchemaType.integer, description: 'Skill rating score 1-100'),
        'certified': Schema(SchemaType.boolean, description: 'Whether certified'),
        'available_date': Schema(SchemaType.string, description: 'Availability date (YYYY-MM-DD)'),
        'available_hours': Schema(SchemaType.number, description: 'Available work hours (default 8)'),
        'reserved_hours': Schema(SchemaType.number, description: 'Reserved/Booked hours'),
        'technicians': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'full_name': Schema(SchemaType.string),
              'employee_no': Schema(SchemaType.string),
              'username': Schema(SchemaType.string),
              'role': Schema(SchemaType.string),
              'department': Schema(SchemaType.string),
              'phone': Schema(SchemaType.string),
              'email': Schema(SchemaType.string),
              'skills': Schema(SchemaType.array, items: Schema(SchemaType.string)),
            },
            requiredProperties: ['full_name'],
          ),
          description: 'Array of technician objects for bulk registration/import',
        ),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _manageWorkProcessesTool = FunctionDeclaration(
    'manage_work_processes',
    'Manage, create, and import machine standard operating procedures (SOP), Job Safety Analysis (JSA), and operation step checklists (create_process, import_sop, import_sop_bulk, add_steps, delete_process).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'create_process, import_sop, import_sop_bulk, add_steps, delete_process'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No (e.g. "MC-01") or Machine ID'),
        'process_no': Schema(SchemaType.string, description: 'Unique SOP process number (e.g. "SOP-MC01")'),
        'title': Schema(SchemaType.string, description: 'Title of the SOP or JSA process'),
        'company': Schema(SchemaType.string, description: 'Company name'),
        'factory': Schema(SchemaType.string, description: 'Factory/Plant name'),
        'department': Schema(SchemaType.string, description: 'Department name'),
        'method_type': Schema(SchemaType.string, description: 'current or improved'),
        'work_type': Schema(SchemaType.string, description: 'standard or maintenance'),
        'notes': Schema(SchemaType.string, description: 'Notes or safety overview'),
        'steps': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'step_no': Schema(SchemaType.integer, description: 'Step sequence number 1, 2, 3...'),
              'description': Schema(SchemaType.string, description: 'Task or safety action description. Required.'),
              'duration_minutes': Schema(SchemaType.number, description: 'Duration in minutes'),
              'value_type': Schema(SchemaType.string, description: 'va, nva, or nnva'),
              'problem_cause': Schema(SchemaType.string, description: 'Identified safety risk or hazard from JSA'),
              'improvement_idea': Schema(SchemaType.string, description: 'Safety preventive measure or control from JSA'),
              'tools_used': Schema(SchemaType.string, description: 'Tools or PPE required'),
            },
            requiredProperties: ['description'],
          ),
          description: 'List of operation/safety steps for this machine',
        ),
        'processes': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No'),
              'process_no': Schema(SchemaType.string),
              'title': Schema(SchemaType.string),
              'steps': Schema(
                SchemaType.array,
                items: Schema(
                  SchemaType.object,
                  properties: {
                    'step_no': Schema(SchemaType.integer),
                    'description': Schema(SchemaType.string),
                    'duration_minutes': Schema(SchemaType.number),
                    'problem_cause': Schema(SchemaType.string),
                    'improvement_idea': Schema(SchemaType.string),
                  },
                  requiredProperties: ['description'],
                ),
              ),
            },
            requiredProperties: ['machine_identifier'],
          ),
          description: 'Array of processes when bulk importing for multiple machines',
        ),
      },
      requiredProperties: ['action'],
    ),
  );

  static final _registerMachinesTool = FunctionDeclaration(
    'register_machines',
    'Register or import new machine records and specs into the MASAPP database machines table from document text or user input.',
    Schema(
      SchemaType.object,
      properties: {
        'machines': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'machine_no': Schema(SchemaType.string, description: 'Unique machine code/ID, e.g. "MC-01" or "CNC-001". Required.'),
              'machine_name': Schema(SchemaType.string, description: 'Name of machine, e.g. "CNC Milling Center"'),
              'asset_no': Schema(SchemaType.string, description: 'Asset/Property tag number if available'),
              'brand': Schema(SchemaType.string, description: 'Brand/Manufacturer, e.g. "FANUC", "MITSUBISHI"'),
              'model': Schema(SchemaType.string, description: 'Model name or number'),
              'serial_no': Schema(SchemaType.string, description: 'Serial number'),
              'location': Schema(SchemaType.string, description: 'Installation area/room/line'),
              'status': Schema(SchemaType.string, description: 'Status: normal, breakdown, pm, offline'),
              'notes': Schema(SchemaType.string, description: 'Additional remarks or specs summary'),
            },
            requiredProperties: ['machine_no'],
          ),
          description: 'Array of machine objects to register/import.',
        ),
      },
      requiredProperties: ['machines'],
    ),
  );

  static final _createPmPlansTool = FunctionDeclaration(
    'create_pm_plans',
    'Create or import a Preventive Maintenance (PM) or Autonomous Maintenance (AM) master plan and task checklist for a machine.',
    Schema(
      SchemaType.object,
      properties: {
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No (e.g. "AP-01") or ID to attach the PM plan to. Required.'),
        'plan_name': Schema(SchemaType.string, description: 'Title of the PM plan (e.g. "PM ประจำเดือนเครื่องตัดเลเซอร์")'),
        'plan_type': Schema(SchemaType.string, description: 'PM (Preventive) or AM (Autonomous). Default PM.'),
        'frequency_days': Schema(SchemaType.integer, description: 'Frequency in days (e.g. 7 for weekly, 30 for monthly, 90 for quarterly, 365 for yearly)'),
        'tasks': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'task_name': Schema(SchemaType.string, description: 'Description of the checklist task, e.g. "ตรวจเช็กระดับน้ำมันไฮดรอลิก"'),
              'task_type': Schema(SchemaType.string, description: 'inspect, clean, lubricate, tighten, replace, calibrate'),
              'is_critical': Schema(SchemaType.boolean, description: 'Whether this task is a critical safety/quality point'),
            },
            requiredProperties: ['task_name'],
          ),
          description: 'List of inspection and maintenance tasks.',
        ),
      },
      requiredProperties: ['machine_identifier', 'tasks'],
    ),
  );

  static final _registerSparePartsTool = FunctionDeclaration(
    'register_spare_parts',
    'Register or import spare parts, consumable items, and BOM catalog into the MASAPP spare_parts table.',
    Schema(
      SchemaType.object,
      properties: {
        'machine_identifier': Schema(SchemaType.string, description: 'Optional Machine code/No (e.g. "AP-01") to link these spare parts to.'),
        'parts': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'part_code': Schema(SchemaType.string, description: 'Part number/SKU/Code (e.g. "FLT-0045")'),
              'part_name': Schema(SchemaType.string, description: 'Name of spare part (e.g. "ไส้กรองอากาศ Air Filter")'),
              'category': Schema(SchemaType.string, description: 'mechanical, electrical, pneumatic, hydraulic, consumable'),
              'unit_cost': Schema(SchemaType.number, description: 'Estimated unit cost in Baht'),
              'reorder_level': Schema(SchemaType.integer, description: 'Minimum stock reorder point (default 5)'),
              'initial_quantity': Schema(SchemaType.integer, description: 'Initial stock on hand quantity (default 0)'),
            },
            requiredProperties: ['part_name'],
          ),
          description: 'List of spare parts to register.',
        ),
      },
      requiredProperties: ['parts'],
    ),
  );

  static final _createWorkOrderTool = FunctionDeclaration(
    'create_work_order',
    'Create and dispatch a new maintenance work order (ใบแจ้งซ่อม) into MASAPP work_orders table from reported machine breakdown or user request.',
    Schema(
      SchemaType.object,
      properties: {
        'title': Schema(SchemaType.string, description: 'Brief title of the repair job (e.g. "ปั๊มน้ำมันไฮดรอลิกรั่วซึม")'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No (e.g. "AP-01") or ID'),
        'symptom': Schema(SchemaType.string, description: 'Observed breakdown symptom or error code'),
        'priority': Schema(SchemaType.string, description: 'urgent (หยุดสายการผลิต), high, normal, low'),
        'description': Schema(SchemaType.string, description: 'Full detailed description of the problem'),
      },
      requiredProperties: ['title', 'symptom'],
    ),
  );

  static final _searchVectorKnowledgeTool = FunctionDeclaration(
    'search_vector_knowledge',
    'Search semantic knowledge vectors for historical troubleshooting, failure symptoms, repair solutions, RCA, and machine manuals.',
    Schema(
      SchemaType.object,
      properties: {
        'query': Schema(
          SchemaType.string,
          description:
              'Search query describing symptoms, breakdown details, error code, machine issue, or maintenance procedure.',
        ),
        'category': Schema(
          SchemaType.string,
          description:
              'Optional category filter: repair_history, machine_specs, pm_standard, or manual.',
        ),
        'top_k': Schema(
          SchemaType.integer,
          description: 'Maximum number of top relevant vector matches to return (default 5).',
        ),
      },
      requiredProperties: ['query'],
    ),
  );

  static final _queryDbTool = FunctionDeclaration(
    'query_database',
    'Execute a SQLite SELECT query on the MASAPP database to retrieve '
        'operational data. Only SELECT statements allowed. Results capped at 200 rows.',
    Schema(
      SchemaType.object,
      properties: {
        'sql': Schema(
          SchemaType.string,
          description:
              'A valid SQLite SELECT statement. Must start with SELECT.',
        ),
        'description': Schema(
          SchemaType.string,
          description: 'Brief description of what this query is for.',
        ),
      },
      requiredProperties: ['sql'],
    ),
  );

  static final _getTablesTool = FunctionDeclaration(
    'get_available_tables',
    'Get a list of all database tables the AI can query, with their column names.',
    Schema(SchemaType.object, properties: {}),
  );

  static final _getSchemaTool = FunctionDeclaration(
    'get_table_schema',
    'Get column names and data types for a specific table.',
    Schema(
      SchemaType.object,
      properties: {
        'table_name': Schema(
          SchemaType.string,
          description: 'The table name to inspect.',
        ),
      },
      requiredProperties: ['table_name'],
    ),
  );

  static final _externalWebSearchTool = FunctionDeclaration(
    'search_external_web',
    'Search external sources only after checking the MASAPP database first or when the user explicitly asks for external information. Returns clearly labeled external data.',
    Schema(
      SchemaType.object,
      properties: {
        'query': Schema(
          SchemaType.string,
          description: 'Search query for external web lookup.',
        ),
        'db_context': Schema(
          SchemaType.string,
          description:
              'Short summary of what was checked in the MASAPP database first.',
        ),
        'why_external_needed': Schema(
          SchemaType.string,
          description:
              'Why external search is necessary after checking the database.',
        ),
        'max_results': Schema(
          SchemaType.integer,
          description: 'Maximum number of results to return.',
        ),
      },
      requiredProperties: ['query', 'db_context', 'why_external_needed'],
    ),
  );

  static final _extractDocumentTextTool = FunctionDeclaration(
    'extract_document_text',
    'Extract full text, pages, or spreadsheet tables from any local document (PDF, Excel xlsx/xls, CSV, TXT, JSON, Markdown).',
    Schema(
      SchemaType.object,
      properties: {
        'file_path': Schema(
          SchemaType.string,
          description:
              'Absolute or relative local file path to read and extract text from.',
        ),
        'max_pages': Schema(
          SchemaType.integer,
          description: 'Maximum number of pages to extract (default: 50).',
        ),
      },
      requiredProperties: ['file_path'],
    ),
  );

  static final _findMachineAssetsTool = FunctionDeclaration(
    'find_machine_assets',
    'Find manuals, PDFs, attachments, and images related to a machine by machine number, name, asset number, brand, model, or serial number.',
    Schema(
      SchemaType.object,
      properties: {
        'query': Schema(
          SchemaType.string,
          description:
              'Machine identifier or search text, such as machine number, name, brand, model, or serial number.',
        ),
        'asset_type': Schema(
          SchemaType.string,
          description: 'Optional filter: all, document, pdf, or image.',
        ),
      },
      requiredProperties: ['query'],
    ),
  );

  static final _externalImageSearchTool = FunctionDeclaration(
    'search_external_images',
    'Search external image sources only after checking the MASAPP database first or when the user explicitly asks for outside images. Returns clearly labeled external image data.',
    Schema(
      SchemaType.object,
      properties: {
        'query': Schema(SchemaType.string, description: 'Image search query.'),
        'db_context': Schema(
          SchemaType.string,
          description:
              'Short summary of what was checked in the MASAPP database first.',
        ),
        'why_external_needed': Schema(
          SchemaType.string,
          description:
              'Why external image search is necessary after checking the database.',
        ),
        'max_results': Schema(
          SchemaType.integer,
          description: 'Maximum number of images to return.',
        ),
      },
      requiredProperties: ['query', 'db_context', 'why_external_needed'],
    ),
  );

  static final _manageMachineAssetsTool = FunctionDeclaration(
    'manage_machine_assets',
    'Attach, update, or remove files, PDFs, manuals, and photos for a machine in the database (action: attach_document, remove_document, set_cover_image).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(
          SchemaType.string,
          description: 'attach_document, remove_document, set_cover_image',
        ),
        'machine_identifier': Schema(
          SchemaType.string,
          description: 'Machine code/No (e.g. "DP-01", "DP 01") or ID',
        ),
        'file_path': Schema(
          SchemaType.string,
          description: 'Local storage or original path to the file to attach',
        ),
        'file_name': Schema(
          SchemaType.string,
          description: 'Display name of the file',
        ),
        'category': Schema(
          SchemaType.string,
          description: 'manual, drawing, inspection, cover, attachment',
        ),
        'attachment_id': Schema(
          SchemaType.string,
          description: 'Attachment ID for removal',
        ),
      },
      requiredProperties: ['action', 'machine_identifier'],
    ),
  );

  static final _generateChartTool = FunctionDeclaration(
    'generate_chart',
    'Generate interactive visual charts (bar, pie, donut, line, area) for maintenance statistics, breakdown counts, OEE trends, spare part consumption, etc.',
    Schema(
      SchemaType.object,
      properties: {
        'chart_type': Schema(SchemaType.string, description: 'Chart type: bar, pie, donut, line, area'),
        'title': Schema(SchemaType.string, description: 'Title of chart in Thai or English'),
        'subtitle': Schema(SchemaType.string, description: 'Optional subtitle or timeframe description'),
        'x_label': Schema(SchemaType.string, description: 'X-axis label (for bar/line charts)'),
        'y_label': Schema(SchemaType.string, description: 'Y-axis label (for bar/line charts)'),
        'unit': Schema(SchemaType.string, description: 'Data unit suffix (e.g. "ครั้ง", "%", "บาท", "ชิ้น", "ชม.")'),
        'data': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'label': Schema(SchemaType.string, description: 'Category or X-axis label'),
              'value': Schema(SchemaType.number, description: 'Numeric value for this item'),
              'color': Schema(SchemaType.string, description: 'Optional hex color (e.g. "#2196F3")'),
              'secondary_value': Schema(SchemaType.number, description: 'Optional secondary value for comparison'),
              'group': Schema(SchemaType.string, description: 'Optional group name'),
            },
            requiredProperties: ['label', 'value'],
          ),
          description: 'Array of data points to plot in the chart',
        ),
      },
      requiredProperties: ['chart_type', 'title', 'data'],
    ),
  );

  static final _subagentQueryDbTool = FunctionDeclaration(
    'subagent_query_database',
    'Delegate high-volume data retrieval to Sub-agent workers to split large database queries into safe batch chunks with live progress and aggregation without token truncation.',
    Schema(
      SchemaType.object,
      properties: {
        'task_description': Schema(SchemaType.string, description: 'Human-readable description of what the subagents are fetching (e.g. "ดึงสถิติงานซ่อมย้อนหลัง 1 ปี")'),
        'queries': Schema(
          SchemaType.array,
          items: Schema(SchemaType.string),
          description: 'List of partitioned SQL SELECT queries to execute in chunks',
        ),
        'sql': Schema(SchemaType.string, description: 'Base SQL query if letting subagent auto-partition by pagination'),
        'split_count': Schema(SchemaType.integer, description: 'Number of chunks/partitions (default 4)'),
      },
      requiredProperties: ['task_description'],
    ),
  );

  static final _generatePresentationSlidesTool = FunctionDeclaration(
    'generate_presentation_slides',
    'Synthesize multi-domain maintenance data and generate an Executive Presentation Deck exported as A4 Landscape (16:9) PDF with Thai font support, KPI cards, Fishbone 4M1E, 5-Why, and 8D problem solving slides.',
    Schema(
      SchemaType.object,
      properties: {
        'title': Schema(SchemaType.string, description: 'Presentation title (e.g. "สรุปผลการดำเนินงานและ KPI ประจำเดือน")'),
        'subtitle': Schema(SchemaType.string, description: 'Subtitle, department, or evaluation period'),
        'author': Schema(SchemaType.string, description: 'Presenter / department name'),
        'theme': Schema(SchemaType.string, description: 'Color theme: blue (corporate), teal (lean/green), purple (executive), orange (urgent/RCA)'),
        'machine_identifier': Schema(SchemaType.string, description: 'Optional specific machine identifier if focusing on a particular machine'),
        'source_references': Schema(
          SchemaType.array,
          items: Schema(SchemaType.string),
          description: 'Grounded source tables or documents referenced in the presentation',
        ),
        'slides': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'slide_type': Schema(SchemaType.string, description: 'Type: title, kpi, fishbone, rca_5why, eight_d, chart, table, content, summary'),
              'title': Schema(SchemaType.string, description: 'Slide title in Thai'),
              'subtitle': Schema(SchemaType.string, description: 'Optional slide subtitle'),
              'content': Schema(SchemaType.string, description: 'Main text description or takeaway notes'),
              'metrics': Schema(
                SchemaType.array,
                items: Schema(SchemaType.object),
                description: 'KPI metric items: [{"label": "OEE", "value": "88.4%", "target": "85%", "status": "good", "change": "+3.4%"}]',
              ),
              'fishbone_data': Schema(
                SchemaType.object,
                description: 'Ishikawa 4M1E data: {"problem": "...", "man": [...], "machine": [...], "method": [...], "material": [...], "environment": [...]}',
              ),
              'five_why_data': Schema(
                SchemaType.object,
                description: '5-Why RCA data: {"problem": "...", "whys": ["Why 1", "Why 2", ...], "root_cause": "...", "countermeasure": "..."}',
              ),
              'eight_d_data': Schema(
                SchemaType.array,
                items: Schema(SchemaType.object),
                description: '8D steps: [{"step": "D1", "title": "ทีมงาน", "description": "...", "owner": "...", "status": "..."}]',
              ),
              'chart_data': Schema(SchemaType.object, description: 'Chart definition if slide_type is chart'),
              'table_data': Schema(SchemaType.object, description: 'Table data with headers and rows if slide_type is table'),
              'action_items': Schema(
                SchemaType.array,
                items: Schema(SchemaType.string),
                description: 'List of next action items if slide_type is summary',
              ),
            },
            requiredProperties: ['slide_type', 'title'],
          ),
          description: 'List of slides in sequential order',
        ),
      },
      requiredProperties: ['title'],
    ),
  );

  static final _manageLineBalancingTool = FunctionDeclaration(
    'manage_line_balancing',
    'Design, generate, update, or optimize Production Lines & Line Balancing workstations. Always query existing machines first and link their machine_id/machine_no to each station. Automatically calculates zero-overflow centered grid layout coordinates so nodes never drop off the canvas edges.',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'generate_line, create_line, update_line, link_machines, auto_layout, get_lines, get_line_details'),
        'line_id': Schema(SchemaType.string, description: 'Unique line ID (e.g. "main_line" or custom ID)'),
        'line_name': Schema(SchemaType.string, description: 'Production line name (e.g. "สายการผลิตหลัก (Main Line)", "Line A - ชิ้นส่วนยานยนต์")'),
        'department': Schema(SchemaType.string, description: 'Department or factory section'),
        'available_time_min': Schema(SchemaType.number, description: 'Total work time available in minutes per day (default 480)'),
        'demand_quantity': Schema(SchemaType.number, description: 'Target demand quantity per day (default 1000)'),
        'electricity_rate': Schema(SchemaType.number, description: 'Electricity cost per kWh (default 4.0)'),
        'fuel_rate': Schema(SchemaType.number, description: 'Fuel cost per unit (default 30.0)'),
        'stations': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'station_no': Schema(SchemaType.integer, description: 'Station sequence number (1, 2, 3...)'),
              'station_name': Schema(SchemaType.string, description: 'Station name (e.g. "1. ตัดและเตรียมวัตถุดิบ (Cutting)")'),
              'machine_identifier': Schema(SchemaType.string, description: 'Code/No or ID of existing machine in database (e.g. "GM-04", "MC-01", "CNC-02"). MUST reuse existing machines from DB!'),
              'cycle_time_sec': Schema(SchemaType.number, description: 'Cycle time in seconds (e.g. 25.0)'),
              'workers': Schema(SchemaType.integer, description: 'Number of operators at this station (default 1)'),
              'event_type': Schema(SchemaType.string, description: 'operation, inspection, transport, delay, storage'),
              'value_type': Schema(SchemaType.string, description: 'va, nva, nnva'),
              'waiting_time_sec': Schema(SchemaType.number, description: 'Buffer/waiting time in seconds'),
              'buffer_quantity': Schema(SchemaType.integer, description: 'WIP buffer quantity before station'),
            },
            requiredProperties: ['station_name', 'cycle_time_sec'],
          ),
          description: 'List of workstations in sequential order in the production line',
        ),
      },
    ),
  );

  static final _openAiTools = [
    {
      'type': 'function',
      'function': {
        'name': 'extract_document_text',
        'description':
            'Extract full text, pages, or spreadsheet tables from any local document (PDF, Excel xlsx/xls, CSV, TXT, JSON, Markdown).',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {
              'type': 'string',
              'description':
                  'Absolute or relative local file path to read and extract text from.',
            },
            'max_pages': {
              'type': 'integer',
              'description': 'Maximum number of pages to extract (default: 50).',
            },
          },
          'required': ['file_path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_machine_assets',
        'description':
            'Attach, update, or remove files, PDFs, manuals, and photos for a machine in the database (action: attach_document, remove_document, set_cover_image).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'description': 'attach_document, remove_document, set_cover_image',
            },
            'machine_identifier': {
              'type': 'string',
              'description': 'Machine code/No (e.g. "DP-01", "DP 01") or ID',
            },
            'file_path': {
              'type': 'string',
              'description': 'Local storage or original path to the file to attach',
            },
            'file_name': {
              'type': 'string',
              'description': 'Display name of the file',
            },
            'category': {
              'type': 'string',
              'description': 'manual, drawing, inspection, cover, attachment',
            },
            'attachment_id': {
              'type': 'string',
              'description': 'Attachment ID for removal',
            },
          },
          'required': ['action', 'machine_identifier'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_machines',
        'description': 'Manage machine records (Insert, Update, Delete/Deactivate, and Specs) in MASAPP database. Supports bulk import array.',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'insert, update, delete'},
            'machine_identifier': {'type': 'string', 'description': 'Machine code/No (e.g. "MC-01") or ID'},
            'machine_no': {'type': 'string', 'description': 'Unique machine code/ID'},
            'machine_name': {'type': 'string', 'description': 'Name of machine'},
            'asset_no': {'type': 'string', 'description': 'Asset tag number'},
            'brand': {'type': 'string', 'description': 'Brand/Manufacturer'},
            'model': {'type': 'string', 'description': 'Model'},
            'serial_no': {'type': 'string', 'description': 'Serial number'},
            'location': {'type': 'string', 'description': 'Installation area/room/line'},
            'status': {'type': 'string', 'description': 'normal, breakdown, pm, offline'},
            'notes': {'type': 'string', 'description': 'Additional remarks or specs summary'},
            'power_kw': {'type': 'number', 'description': 'Power in kW'},
            'voltage_v': {'type': 'number', 'description': 'Voltage in V'},
            'current_a': {'type': 'number', 'description': 'Current in A'},
            'frequency_hz': {'type': 'number', 'description': 'Frequency in Hz'},
            'capacity': {'type': 'number', 'description': 'Capacity value'},
            'capacity_unit': {'type': 'string', 'description': 'Capacity unit'},
            'weight_kg': {'type': 'number', 'description': 'Weight in kg'},
            'dim_length_mm': {'type': 'number', 'description': 'Length in mm'},
            'dim_width_mm': {'type': 'number', 'description': 'Width in mm'},
            'dim_height_mm': {'type': 'number', 'description': 'Height in mm'},
            'rpm': {'type': 'number', 'description': 'Spindle/motor speed in RPM'},
            'fuel_consumption_rate': {'type': 'number', 'description': 'Fuel consumption rate L/hr'},
            'fuel_type': {'type': 'string', 'description': 'Fuel type'},
            'default_workers': {'type': 'integer', 'description': 'Required workers'},
            'extra_specs': {'type': 'string', 'description': 'Extra specs JSON or description'},
            'machines': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'machine_no': {'type': 'string'},
                  'machine_name': {'type': 'string'},
                  'asset_no': {'type': 'string'},
                  'brand': {'type': 'string'},
                  'model': {'type': 'string'},
                  'serial_no': {'type': 'string'},
                  'location': {'type': 'string'},
                  'status': {'type': 'string'},
                  'notes': {'type': 'string'},
                  'power_kw': {'type': 'number'},
                  'voltage_v': {'type': 'number'},
                  'current_a': {'type': 'number'},
                  'frequency_hz': {'type': 'number'},
                  'capacity': {'type': 'number'},
                  'capacity_unit': {'type': 'string'},
                  'weight_kg': {'type': 'number'},
                  'dim_length_mm': {'type': 'number'},
                  'dim_width_mm': {'type': 'number'},
                  'dim_height_mm': {'type': 'number'},
                  'rpm': {'type': 'number'},
                  'fuel_consumption_rate': {'type': 'number'},
                  'fuel_type': {'type': 'string'},
                  'default_workers': {'type': 'integer'},
                  'extra_specs': {'type': 'string'},
                },
                'required': ['machine_no'],
              },
            },
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_locations',
        'description': 'Manage factory layouts, zones, and machine positions (create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position). Supports bulk zones and bulk machine_positions.',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position'},
            'layout_id': {'type': 'string'},
            'layout_name': {'type': 'string'},
            'description': {'type': 'string'},
            'floor_no': {'type': 'integer'},
            'width_m': {'type': 'number'},
            'height_m': {'type': 'number'},
            'zone_name': {'type': 'string'},
            'zone_type': {'type': 'string'},
            'x_start': {'type': 'number'},
            'y_start': {'type': 'number'},
            'x_end': {'type': 'number'},
            'y_end': {'type': 'number'},
            'background_color': {'type': 'string'},
            'border_color': {'type': 'string'},
            'zones': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'zone_name': {'type': 'string'},
                  'zone_type': {'type': 'string'},
                  'x_start': {'type': 'number'},
                  'y_start': {'type': 'number'},
                  'x_end': {'type': 'number'},
                  'y_end': {'type': 'number'},
                  'background_color': {'type': 'string'},
                  'border_color': {'type': 'string'},
                },
                'required': ['zone_name'],
              },
            },
            'machine_identifier': {'type': 'string'},
            'zone_id': {'type': 'string'},
            'x_position': {'type': 'number'},
            'y_position': {'type': 'number'},
            'width': {'type': 'number'},
            'height': {'type': 'number'},
            'status_color': {'type': 'string'},
            'machine_positions': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'machine_identifier': {'type': 'string'},
                  'machine_no': {'type': 'string'},
                  'zone_id': {'type': 'string'},
                  'zone_name': {'type': 'string'},
                  'x_position': {'type': 'number'},
                  'y_position': {'type': 'number'},
                  'width': {'type': 'number'},
                  'height': {'type': 'number'},
                  'status_color': {'type': 'string'},
                },
              },
            },
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_pm_plans',
        'description': 'Manage PM/AM master plans and checklist tasks (create_plan, update_plan, delete_plan, add_task, delete_task).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_plan, update_plan, delete_plan, add_task, delete_task'},
            'plan_identifier': {'type': 'string'},
            'machine_identifier': {'type': 'string'},
            'plan_name': {'type': 'string'},
            'plan_type': {'type': 'string'},
            'frequency_days': {'type': 'integer'},
            'task_name': {'type': 'string'},
            'task_type': {'type': 'string'},
            'is_critical': {'type': 'boolean'},
            'tasks': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'task_name': {'type': 'string'},
                  'task_type': {'type': 'string'},
                  'is_critical': {'type': 'boolean'},
                },
                'required': ['task_name'],
              },
            },
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_pm_schedules',
        'description': 'Manage PM/AM schedules and task execution logs (create_schedule, update_status, record_execution, delete_schedule).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_schedule, update_status, record_execution, delete_schedule'},
            'schedule_id': {'type': 'string'},
            'plan_identifier': {'type': 'string'},
            'scheduled_date': {'type': 'string'},
            'assigned_to': {'type': 'string'},
            'status': {'type': 'string'},
            'task_name': {'type': 'string'},
            'result': {'type': 'string'},
            'remarks': {'type': 'string'},
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_work_orders',
        'description': 'Manage maintenance work orders (create_order, update_order, record_labor, record_rca, delete_order).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_order, update_order, record_labor, record_rca, delete_order'},
            'wo_identifier': {'type': 'string'},
            'machine_identifier': {'type': 'string'},
            'title': {'type': 'string'},
            'symptom': {'type': 'string'},
            'priority': {'type': 'string'},
            'status': {'type': 'string'},
            'assigned_to': {'type': 'string'},
            'failure_cause': {'type': 'string'},
            'technician_identifier': {'type': 'string'},
            'labor_hours': {'type': 'number'},
            'task_description': {'type': 'string'},
            'root_cause': {'type': 'string'},
            'why_1': {'type': 'string'},
            'why_2': {'type': 'string'},
            'why_3': {'type': 'string'},
            'why_4': {'type': 'string'},
            'why_5': {'type': 'string'},
            'correction_action': {'type': 'string'},
            'preventive_action': {'type': 'string'},
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_contractors',
        'description': 'Manage outsource vendors and contractors (create_contractor, update_contractor, delete_contractor).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_contractor, update_contractor, delete_contractor'},
            'contractor_identifier': {'type': 'string'},
            'name': {'type': 'string'},
            'contact_name': {'type': 'string'},
            'phone': {'type': 'string'},
            'email': {'type': 'string'},
            'service_scope': {'type': 'string'},
            'is_approved': {'type': 'boolean'},
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_work_permits',
        'description': 'Manage electronic work permits and safety checks (create_permit, update_status, update_safety_check, delete_permit).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_permit, update_status, update_safety_check, delete_permit'},
            'permit_identifier': {'type': 'string'},
            'permit_type': {'type': 'string'},
            'description': {'type': 'string'},
            'machine_identifier': {'type': 'string'},
            'duration_hours': {'type': 'integer'},
            'status': {'type': 'string'},
            'check_item': {'type': 'string'},
            'is_passed': {'type': 'boolean'},
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_spare_parts',
        'description': 'Manage spare parts catalog, stock movement transactions, and BOM mapping (create_part, update_part, delete_part, record_transaction, link_machine).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_part, update_part, delete_part, record_transaction, link_machine'},
            'part_identifier': {'type': 'string'},
            'part_code': {'type': 'string'},
            'part_name': {'type': 'string'},
            'category': {'type': 'string'},
            'unit_cost': {'type': 'number'},
            'reorder_level': {'type': 'integer'},
            'initial_quantity': {'type': 'integer'},
            'location': {'type': 'string'},
            'trans_type': {'type': 'string'},
            'quantity': {'type': 'integer'},
            'machine_identifier': {'type': 'string'},
            'remarks': {'type': 'string'},
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_tools',
        'description': 'Manage tools, equipment, check-out/check-in, and repair transactions (create_tool, update_tool, delete_tool, record_transaction).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_tool, update_tool, delete_tool, record_transaction'},
            'tool_identifier': {'type': 'string'},
            'tool_code': {'type': 'string'},
            'tool_name': {'type': 'string'},
            'category': {'type': 'string'},
            'status': {'type': 'string'},
            'price': {'type': 'number'},
            'action_type': {'type': 'string'},
            'notes': {'type': 'string'},
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_oee_logs',
        'description': 'Manage OEE production and machine running hour logs (record_log, update_log, delete_log).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'record_log, update_log, delete_log'},
            'hours_id': {'type': 'string'},
            'machine_identifier': {'type': 'string'},
            'recorded_date': {'type': 'string'},
            'cumulative_hours': {'type': 'number'},
            'daily_hours': {'type': 'number'},
            'target_production': {'type': 'number'},
            'actual_production': {'type': 'number'},
            'good_production': {'type': 'number'},
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_technicians',
        'description': 'Manage technician records, skill matrix, scoring, availability, and workforce directory in MASAPP database (create_technician, update_technician, delete_technician, add_skill, update_skill, rate_skill, delete_skill, set_availability).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_technician, update_technician, delete_technician, add_skill, update_skill, rate_skill, delete_skill, set_availability'},
            'technician_identifier': {'type': 'string'},
            'full_name': {'type': 'string'},
            'employee_no': {'type': 'string'},
            'username': {'type': 'string'},
            'role': {'type': 'string'},
            'department': {'type': 'string'},
            'phone': {'type': 'string'},
            'email': {'type': 'string'},
            'skill_name': {'type': 'string'},
            'skills': {'type': 'array', 'items': {'type': 'string'}},
            'proficiency_level': {'type': 'string'},
            'score': {'type': 'integer'},
            'certified': {'type': 'boolean'},
            'available_date': {'type': 'string'},
            'available_hours': {'type': 'number'},
            'reserved_hours': {'type': 'number'},
            'technicians': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'full_name': {'type': 'string'},
                  'employee_no': {'type': 'string'},
                  'username': {'type': 'string'},
                  'role': {'type': 'string'},
                  'department': {'type': 'string'},
                  'phone': {'type': 'string'},
                  'email': {'type': 'string'},
                  'skills': {'type': 'array', 'items': {'type': 'string'}},
                },
                'required': ['full_name'],
              },
            },
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_work_processes',
        'description': 'Manage, create, and import machine standard operating procedures (SOP), Job Safety Analysis (JSA), and operation step checklists (create_process, import_sop, import_sop_bulk, add_steps, delete_process).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'create_process, import_sop, import_sop_bulk, add_steps, delete_process'},
            'machine_identifier': {'type': 'string', 'description': 'Machine code/No (e.g. "MC-01")'},
            'process_no': {'type': 'string'},
            'title': {'type': 'string'},
            'company': {'type': 'string'},
            'factory': {'type': 'string'},
            'department': {'type': 'string'},
            'method_type': {'type': 'string'},
            'work_type': {'type': 'string'},
            'notes': {'type': 'string'},
            'steps': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'step_no': {'type': 'integer'},
                  'description': {'type': 'string'},
                  'duration_minutes': {'type': 'number'},
                  'value_type': {'type': 'string'},
                  'problem_cause': {'type': 'string'},
                  'improvement_idea': {'type': 'string'},
                  'tools_used': {'type': 'string'},
                },
                'required': ['description'],
              },
            },
            'processes': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'machine_identifier': {'type': 'string'},
                  'process_no': {'type': 'string'},
                  'title': {'type': 'string'},
                  'steps': {'type': 'array', 'items': {'type': 'object'}},
                },
                'required': ['machine_identifier'],
              },
            },
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'query_database',
        'description': 'Execute a SQLite SELECT query on the MASAPP database to retrieve operational data. Only SELECT statements allowed. Results capped at 200 rows.',
        'parameters': {
          'type': 'object',
          'properties': {
            'sql': {'type': 'string', 'description': 'A valid SQLite SELECT statement.'},
            'description': {'type': 'string'},
          },
          'required': ['sql'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_available_tables',
        'description': 'Get a list of all database tables the AI can query, with their column names.',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_table_schema',
        'description': 'Get column names and data types for a specific table.',
        'parameters': {
          'type': 'object',
          'properties': {
            'table_name': {'type': 'string', 'description': 'The table name to inspect.'},
          },
          'required': ['table_name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_vector_knowledge',
        'description': 'Search semantic knowledge vectors for historical troubleshooting, failure symptoms, repair solutions, RCA, and machine manuals.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Search query describing symptoms, breakdown details, error code, machine issue, or maintenance procedure.'},
            'category': {'type': 'string'},
            'top_k': {'type': 'integer'},
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'find_machine_assets',
        'description': 'Find manuals, PDFs, attachments, and images related to a machine by machine number, name, asset number, brand, model, or serial number.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'asset_type': {'type': 'string'},
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_external_web',
        'description': 'Search external sources only after checking the MASAPP database first or when the user explicitly asks for external information.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'db_context': {'type': 'string'},
            'why_external_needed': {'type': 'string'},
            'max_results': {'type': 'integer'},
          },
          'required': ['query', 'db_context', 'why_external_needed'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_external_images',
        'description': 'Search external image sources only after checking the MASAPP database first or when the user explicitly asks for outside images.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'db_context': {'type': 'string'},
            'why_external_needed': {'type': 'string'},
            'max_results': {'type': 'integer'},
          },
          'required': ['query', 'db_context', 'why_external_needed'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'generate_chart',
        'description': 'Generate interactive visual charts (bar, pie, donut, line, area) for maintenance statistics, breakdown counts, OEE trends, spare part consumption, etc.',
        'parameters': {
          'type': 'object',
          'properties': {
            'chart_type': {'type': 'string', 'description': 'Chart type: bar, pie, donut, line, area'},
            'title': {'type': 'string', 'description': 'Title of chart in Thai or English'},
            'subtitle': {'type': 'string', 'description': 'Optional subtitle or timeframe description'},
            'x_label': {'type': 'string', 'description': 'X-axis label (for bar/line charts)'},
            'y_label': {'type': 'string', 'description': 'Y-axis label (for bar/line charts)'},
            'unit': {'type': 'string', 'description': 'Data unit suffix (e.g. "ครั้ง", "%", "บาท", "ชิ้น", "ชม.")'},
            'data': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'label': {'type': 'string', 'description': 'Category or X-axis label'},
                  'value': {'type': 'number', 'description': 'Numeric value for this item'},
                  'color': {'type': 'string', 'description': 'Optional hex color (e.g. "#2196F3")'},
                  'secondary_value': {'type': 'number', 'description': 'Optional secondary value'},
                  'group': {'type': 'string', 'description': 'Optional group name'},
                },
                'required': ['label', 'value'],
              },
              'description': 'Array of data points to plot in the chart',
            },
          },
          'required': ['chart_type', 'title', 'data'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'subagent_query_database',
        'description': 'Delegate high-volume data retrieval to Sub-agent workers to split large database queries into safe batch chunks with live progress and aggregation without token truncation.',
        'parameters': {
          'type': 'object',
          'properties': {
            'task_description': {'type': 'string', 'description': 'Description of what subagents are fetching'},
            'queries': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'List of partitioned SQL SELECT queries to execute in chunks',
            },
            'sql': {'type': 'string', 'description': 'Base SQL query if auto-partitioning by pagination'},
            'split_count': {'type': 'integer', 'description': 'Number of chunks (default 4)'},
          },
          'required': ['task_description'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'generate_presentation_slides',
        'description':
            'Synthesize multi-domain maintenance data and generate an Executive Presentation Deck exported as A4 Landscape (16:9) PDF with Thai font support, KPI cards, Fishbone 4M1E, 5-Why, and 8D problem solving slides.',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'Presentation title'},
            'subtitle': {'type': 'string', 'description': 'Optional subtitle'},
            'author': {'type': 'string', 'description': 'Presenter / department'},
            'theme': {'type': 'string', 'description': 'Theme: blue, teal, purple, orange'},
            'machine_identifier': {'type': 'string', 'description': 'Optional specific machine identifier'},
            'source_references': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Grounded source tables or documents referenced',
            },
            'slides': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'slide_type': {'type': 'string', 'description': 'Type: title, kpi, fishbone, rca_5why, eight_d, chart, table, content, summary'},
                  'title': {'type': 'string', 'description': 'Slide title'},
                  'subtitle': {'type': 'string', 'description': 'Slide subtitle'},
                  'content': {'type': 'string', 'description': 'Slide text description'},
                  'metrics': {'type': 'array', 'items': {'type': 'object'}},
                  'fishbone_data': {'type': 'object'},
                  'five_why_data': {'type': 'object'},
                  'eight_d_data': {'type': 'array', 'items': {'type': 'object'}},
                  'chart_data': {'type': 'object'},
                  'table_data': {'type': 'object'},
                  'action_items': {'type': 'array', 'items': {'type': 'string'}},
                },
                'required': ['slide_type', 'title'],
              },
            },
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'manage_line_balancing',
        'description':
            'Design, generate, update, or optimize Production Lines & Line Balancing workstations. Always query existing machines first and link their machine_id/machine_no to each station. Automatically calculates zero-overflow centered grid layout coordinates so nodes never drop off the canvas edges.',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'generate_line, create_line, update_line, link_machines, auto_layout, get_lines, get_line_details'},
            'line_id': {'type': 'string', 'description': 'Unique line ID'},
            'line_name': {'type': 'string', 'description': 'Production line name'},
            'department': {'type': 'string', 'description': 'Department'},
            'available_time_min': {'type': 'number', 'description': 'Work time available in minutes (default 480)'},
            'demand_quantity': {'type': 'number', 'description': 'Target demand per day (default 1000)'},
            'electricity_rate': {'type': 'number', 'description': 'Electricity cost per kWh'},
            'fuel_rate': {'type': 'number', 'description': 'Fuel cost per unit'},
            'stations': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'station_no': {'type': 'integer'},
                  'station_name': {'type': 'string'},
                  'machine_identifier': {'type': 'string', 'description': 'Code/No or ID of existing machine in database. MUST reuse existing machines!'},
                  'cycle_time_sec': {'type': 'number'},
                  'workers': {'type': 'integer'},
                  'event_type': {'type': 'string'},
                  'value_type': {'type': 'string'},
                  'waiting_time_sec': {'type': 'number'},
                  'buffer_quantity': {'type': 'integer'},
                },
                'required': ['station_name', 'cycle_time_sec'],
              },
            },
          },
        },
      },
    },
  ];

  static final _anthropicTools = [
    {
      'name': 'manage_machine_assets',
      'description':
          'Attach, update, or remove files, PDFs, manuals, and photos for a machine in the database (action: attach_document, remove_document, set_cover_image).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': 'attach_document, remove_document, set_cover_image',
          },
          'machine_identifier': {
            'type': 'string',
            'description': 'Machine code/No (e.g. "DP-01", "DP 01") or ID',
          },
          'file_path': {
            'type': 'string',
            'description': 'Local storage or original path to the file to attach',
          },
          'file_name': {
            'type': 'string',
            'description': 'Display name of the file',
          },
          'category': {
            'type': 'string',
            'description': 'manual, drawing, inspection, cover, attachment',
          },
          'attachment_id': {
            'type': 'string',
            'description': 'Attachment ID for removal',
          },
        },
        'required': ['action', 'machine_identifier'],
      },
    },
    {
      'name': 'extract_document_text',
      'description':
          'Extract full text, pages, or spreadsheet tables from any local document (PDF, Excel xlsx/xls, CSV, TXT, JSON, Markdown).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description':
                'Absolute or relative local file path to read and extract text from.',
          },
          'max_pages': {
            'type': 'integer',
            'description': 'Maximum number of pages to extract (default: 50).',
          },
        },
        'required': ['file_path'],
      },
    },
    {
      'name': 'manage_machines',
      'description': 'Manage machine records (Insert, Update, Delete/Deactivate, and Specs) in MASAPP database. Supports bulk import array.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'insert, update, delete'},
          'machine_identifier': {'type': 'string'},
          'machine_no': {'type': 'string'},
          'machine_name': {'type': 'string'},
          'asset_no': {'type': 'string'},
          'brand': {'type': 'string'},
          'model': {'type': 'string'},
          'serial_no': {'type': 'string'},
          'location': {'type': 'string'},
          'status': {'type': 'string'},
          'notes': {'type': 'string'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_locations',
      'description': 'Manage factory layouts, zones, and machine positions (create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position'},
          'layout_name': {'type': 'string'},
          'zone_name': {'type': 'string'},
          'zone_type': {'type': 'string'},
          'machine_identifier': {'type': 'string'},
          'x_position': {'type': 'number'},
          'y_position': {'type': 'number'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_pm_plans',
      'description': 'Manage PM/AM master plans and checklist tasks (create_plan, update_plan, delete_plan, add_task, delete_task).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_plan, update_plan, delete_plan, add_task, delete_task'},
          'plan_identifier': {'type': 'string'},
          'machine_identifier': {'type': 'string'},
          'plan_name': {'type': 'string'},
          'plan_type': {'type': 'string'},
          'frequency_days': {'type': 'integer'},
          'task_name': {'type': 'string'},
          'task_type': {'type': 'string'},
          'is_critical': {'type': 'boolean'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_pm_schedules',
      'description': 'Manage PM/AM schedules and task execution logs (create_schedule, update_status, record_execution, delete_schedule).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_schedule, update_status, record_execution, delete_schedule'},
          'schedule_id': {'type': 'string'},
          'plan_identifier': {'type': 'string'},
          'scheduled_date': {'type': 'string'},
          'assigned_to': {'type': 'string'},
          'status': {'type': 'string'},
          'task_name': {'type': 'string'},
          'result': {'type': 'string'},
          'remarks': {'type': 'string'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_work_orders',
      'description': 'Manage maintenance work orders (create_order, update_order, record_labor, record_rca, delete_order).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_order, update_order, record_labor, record_rca, delete_order'},
          'wo_identifier': {'type': 'string'},
          'machine_identifier': {'type': 'string'},
          'title': {'type': 'string'},
          'symptom': {'type': 'string'},
          'priority': {'type': 'string'},
          'status': {'type': 'string'},
          'assigned_to': {'type': 'string'},
          'failure_cause': {'type': 'string'},
          'technician_identifier': {'type': 'string'},
          'labor_hours': {'type': 'number'},
          'task_description': {'type': 'string'},
          'root_cause': {'type': 'string'},
          'why_1': {'type': 'string'},
          'why_2': {'type': 'string'},
          'why_3': {'type': 'string'},
          'why_4': {'type': 'string'},
          'why_5': {'type': 'string'},
          'correction_action': {'type': 'string'},
          'preventive_action': {'type': 'string'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_contractors',
      'description': 'Manage outsource vendors and contractors (create_contractor, update_contractor, delete_contractor).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_contractor, update_contractor, delete_contractor'},
          'contractor_identifier': {'type': 'string'},
          'name': {'type': 'string'},
          'contact_name': {'type': 'string'},
          'phone': {'type': 'string'},
          'email': {'type': 'string'},
          'service_scope': {'type': 'string'},
          'is_approved': {'type': 'boolean'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_work_permits',
      'description': 'Manage electronic work permits and safety checks (create_permit, update_status, update_safety_check, delete_permit).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_permit, update_status, update_safety_check, delete_permit'},
          'permit_identifier': {'type': 'string'},
          'permit_type': {'type': 'string'},
          'description': {'type': 'string'},
          'machine_identifier': {'type': 'string'},
          'duration_hours': {'type': 'integer'},
          'status': {'type': 'string'},
          'check_item': {'type': 'string'},
          'is_passed': {'type': 'boolean'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_spare_parts',
      'description': 'Manage spare parts catalog, stock movement transactions, and BOM mapping (create_part, update_part, delete_part, record_transaction, link_machine).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_part, update_part, delete_part, record_transaction, link_machine'},
          'part_identifier': {'type': 'string'},
          'part_code': {'type': 'string'},
          'part_name': {'type': 'string'},
          'category': {'type': 'string'},
          'unit_cost': {'type': 'number'},
          'reorder_level': {'type': 'integer'},
          'initial_quantity': {'type': 'integer'},
          'location': {'type': 'string'},
          'trans_type': {'type': 'string'},
          'quantity': {'type': 'integer'},
          'machine_identifier': {'type': 'string'},
          'remarks': {'type': 'string'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_tools',
      'description': 'Manage tools, equipment, check-out/check-in, and repair transactions (create_tool, update_tool, delete_tool, record_transaction).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_tool, update_tool, delete_tool, record_transaction'},
          'tool_identifier': {'type': 'string'},
          'tool_code': {'type': 'string'},
          'tool_name': {'type': 'string'},
          'category': {'type': 'string'},
          'status': {'type': 'string'},
          'price': {'type': 'number'},
          'action_type': {'type': 'string'},
          'notes': {'type': 'string'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_oee_logs',
      'description': 'Manage OEE production and machine running hour logs (record_log, update_log, delete_log).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'record_log, update_log, delete_log'},
          'hours_id': {'type': 'string'},
          'machine_identifier': {'type': 'string'},
          'recorded_date': {'type': 'string'},
          'cumulative_hours': {'type': 'number'},
          'daily_hours': {'type': 'number'},
          'target_production': {'type': 'number'},
          'actual_production': {'type': 'number'},
          'good_production': {'type': 'number'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_technicians',
      'description': 'Manage technician records, skill matrix, scoring, availability, and workforce directory in MASAPP database (create_technician, update_technician, delete_technician, add_skill, update_skill, rate_skill, delete_skill, set_availability).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_technician, update_technician, delete_technician, add_skill, update_skill, rate_skill, delete_skill, set_availability'},
          'technician_identifier': {'type': 'string'},
          'full_name': {'type': 'string'},
          'employee_no': {'type': 'string'},
          'username': {'type': 'string'},
          'role': {'type': 'string'},
          'department': {'type': 'string'},
          'phone': {'type': 'string'},
          'email': {'type': 'string'},
          'skill_name': {'type': 'string'},
          'skills': {'type': 'array', 'items': {'type': 'string'}},
          'proficiency_level': {'type': 'string'},
          'score': {'type': 'integer'},
          'certified': {'type': 'boolean'},
          'available_date': {'type': 'string'},
          'available_hours': {'type': 'number'},
          'reserved_hours': {'type': 'number'},
          'technicians': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'full_name': {'type': 'string'},
                'employee_no': {'type': 'string'},
                'username': {'type': 'string'},
                'role': {'type': 'string'},
                'department': {'type': 'string'},
                'phone': {'type': 'string'},
                'email': {'type': 'string'},
                'skills': {'type': 'array', 'items': {'type': 'string'}},
              },
              'required': ['full_name'],
            },
          },
        },
        'required': ['action'],
      },
    },
    {
      'name': 'manage_work_processes',
      'description':
          'Manage, create, and import machine standard operating procedures (SOP), Job Safety Analysis (JSA), and operation step checklists (create_process, import_sop, import_sop_bulk, add_steps, delete_process).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'create_process, import_sop, import_sop_bulk, add_steps, delete_process'},
          'machine_identifier': {'type': 'string', 'description': 'Machine code/No (e.g. "MC-01")'},
          'process_no': {'type': 'string'},
          'title': {'type': 'string'},
          'company': {'type': 'string'},
          'factory': {'type': 'string'},
          'department': {'type': 'string'},
          'method_type': {'type': 'string'},
          'work_type': {'type': 'string'},
          'notes': {'type': 'string'},
          'steps': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'step_no': {'type': 'integer'},
                'description': {'type': 'string'},
                'duration_minutes': {'type': 'number'},
                'value_type': {'type': 'string'},
                'problem_cause': {'type': 'string'},
                'improvement_idea': {'type': 'string'},
                'tools_used': {'type': 'string'},
              },
              'required': ['description'],
            },
          },
          'processes': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'machine_identifier': {'type': 'string'},
                'process_no': {'type': 'string'},
                'title': {'type': 'string'},
                'steps': {'type': 'array', 'items': {'type': 'object'}},
              },
              'required': ['machine_identifier'],
            },
          },
        },
        'required': ['action'],
      },
    },
    {
      'name': 'query_database',
      'description':
          'Execute a SQLite SELECT query on the MASAPP database to retrieve operational data. Only SELECT statements allowed. Results capped at 200 rows.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'sql': {
            'type': 'string',
            'description':
                'A valid SQLite SELECT statement. Must start with SELECT.',
          },
          'description': {
            'type': 'string',
            'description': 'Brief description of what this query is for.',
          },
        },
        'required': ['sql'],
      },
    },
    {
      'name': 'get_available_tables',
      'description':
          'Get a list of all database tables the AI can query, with their column names.',
      'input_schema': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'get_table_schema',
      'description': 'Get column names and data types for a specific table.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'table_name': {
            'type': 'string',
            'description': 'The table name to inspect.',
          },
        },
        'required': ['table_name'],
      },
    },
    {
      'name': 'search_vector_knowledge',
      'description':
          'Search semantic knowledge vectors for historical troubleshooting, failure symptoms, repair solutions, RCA, and machine manuals.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Search query describing symptoms, breakdown details, error code, machine issue, or maintenance procedure.',
          },
          'category': {'type': 'string'},
          'top_k': {'type': 'integer'},
        },
        'required': ['query'],
      },
    },
    {
      'name': 'find_machine_assets',
      'description':
          'Find manuals, PDFs, attachments, and images related to a machine by machine number, name, asset number, brand, model, or serial number.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Machine identifier or search text, such as machine number, name, brand, model, or serial number.',
          },
          'asset_type': {
            'type': 'string',
            'description': 'Optional filter: all, document, pdf, or image.',
          },
        },
        'required': ['query'],
      },
    },
    {
      'name': 'search_external_web',
      'description':
          'Search external sources only after checking the MASAPP database first or when the user explicitly asks for external information. Returns clearly labeled external data.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search query for external web lookup.',
          },
          'db_context': {
            'type': 'string',
            'description':
                'Short summary of what was checked in the MASAPP database first.',
          },
          'why_external_needed': {
            'type': 'string',
            'description':
                'Why external search is necessary after checking the database.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of results to return.',
          },
        },
        'required': ['query', 'db_context', 'why_external_needed'],
      },
    },
    {
      'name': 'search_external_images',
      'description':
          'Search external image sources only after checking the MASAPP database first or when the user explicitly asks for outside images. Returns clearly labeled external image data.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Image search query.'},
          'db_context': {
            'type': 'string',
            'description':
                'Short summary of what was checked in the MASAPP database first.',
          },
          'why_external_needed': {
            'type': 'string',
            'description':
                'Why external image search is necessary after checking the database.',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of images to return.',
          },
        },
        'required': ['query', 'db_context', 'why_external_needed'],
      },
    },
    {
      'name': 'generate_chart',
      'description':
          'Generate interactive visual charts (bar, pie, donut, line, area) for maintenance statistics, breakdown counts, OEE trends, spare part consumption, etc.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'chart_type': {'type': 'string', 'description': 'Chart type: bar, pie, donut, line, area'},
          'title': {'type': 'string', 'description': 'Title of chart in Thai or English'},
          'subtitle': {'type': 'string', 'description': 'Optional subtitle or timeframe description'},
          'x_label': {'type': 'string', 'description': 'X-axis label (for bar/line charts)'},
          'y_label': {'type': 'string', 'description': 'Y-axis label (for bar/line charts)'},
          'unit': {'type': 'string', 'description': 'Data unit suffix (e.g. "ครั้ง", "%", "บาท", "ชิ้น", "ชม.")'},
          'data': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'label': {'type': 'string', 'description': 'Category or X-axis label'},
                'value': {'type': 'number', 'description': 'Numeric value for this item'},
                'color': {'type': 'string', 'description': 'Optional hex color (e.g. "#2196F3")'},
                'secondary_value': {'type': 'number', 'description': 'Optional secondary value'},
                'group': {'type': 'string', 'description': 'Optional group name'},
              },
              'required': ['label', 'value'],
            },
            'description': 'Array of data points to plot in the chart',
          },
        },
        'required': ['chart_type', 'title', 'data'],
      },
    },
    {
      'name': 'subagent_query_database',
      'description':
          'Delegate high-volume data retrieval to Sub-agent workers to split large database queries into safe batch chunks with live progress and aggregation without token truncation.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'task_description': {'type': 'string', 'description': 'Description of what subagents are fetching'},
          'queries': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'List of partitioned SQL SELECT queries to execute in chunks',
          },
          'sql': {'type': 'string', 'description': 'Base SQL query if auto-partitioning by pagination'},
          'split_count': {'type': 'integer', 'description': 'Number of chunks (default 4)'},
        },
        'required': ['task_description'],
      },
    },
    {
      'name': 'generate_presentation_slides',
      'description':
          'Synthesize multi-domain maintenance data and generate an Executive Presentation Deck exported as A4 Landscape (16:9) PDF with Thai font support, KPI cards, Fishbone 4M1E, 5-Why, and 8D problem solving slides.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Presentation title'},
          'subtitle': {'type': 'string', 'description': 'Optional subtitle'},
          'author': {'type': 'string', 'description': 'Presenter / department'},
          'theme': {'type': 'string', 'description': 'Theme: blue, teal, purple, orange'},
          'machine_identifier': {'type': 'string', 'description': 'Optional specific machine identifier'},
          'source_references': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Grounded source tables or documents referenced',
          },
          'slides': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'slide_type': {'type': 'string', 'description': 'Type: title, kpi, fishbone, rca_5why, eight_d, chart, table, content, summary'},
                'title': {'type': 'string', 'description': 'Slide title'},
                'subtitle': {'type': 'string', 'description': 'Slide subtitle'},
                'content': {'type': 'string', 'description': 'Slide text description'},
                'metrics': {'type': 'array', 'items': {'type': 'object'}},
                'fishbone_data': {'type': 'object'},
                'five_why_data': {'type': 'object'},
                'eight_d_data': {'type': 'array', 'items': {'type': 'object'}},
                'chart_data': {'type': 'object'},
                'table_data': {'type': 'object'},
                'action_items': {'type': 'array', 'items': {'type': 'string'}},
              },
              'required': ['slide_type', 'title'],
            },
          },
        },
        'required': ['title'],
      },
    },
    {
      'name': 'manage_line_balancing',
      'description':
          'Design, generate, update, or optimize Production Lines & Line Balancing workstations. Always query existing machines first and link their machine_id/machine_no to each station. Automatically calculates zero-overflow centered grid layout coordinates so nodes never drop off the canvas edges.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'generate_line, create_line, update_line, link_machines, auto_layout, get_lines, get_line_details'},
          'line_id': {'type': 'string', 'description': 'Unique line ID'},
          'line_name': {'type': 'string', 'description': 'Production line name'},
          'department': {'type': 'string', 'description': 'Department'},
          'available_time_min': {'type': 'number', 'description': 'Work time available in minutes (default 480)'},
          'demand_quantity': {'type': 'number', 'description': 'Target demand per day (default 1000)'},
          'electricity_rate': {'type': 'number', 'description': 'Electricity cost per kWh'},
          'fuel_rate': {'type': 'number', 'description': 'Fuel cost per unit'},
          'stations': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'station_no': {'type': 'integer'},
                'station_name': {'type': 'string'},
                'machine_identifier': {'type': 'string', 'description': 'Code/No or ID of existing machine in database. MUST reuse existing machines!'},
                'cycle_time_sec': {'type': 'number'},
                'workers': {'type': 'integer'},
                'event_type': {'type': 'string'},
                'value_type': {'type': 'string'},
                'waiting_time_sec': {'type': 'number'},
                'buffer_quantity': {'type': 'integer'},
              },
              'required': ['station_name', 'cycle_time_sec'],
            },
          },
        },
      },
    },
  ];

  static Future<AiProviderConfig> loadConfig() async {
    final provider = AiProviderCatalog.fromId(
      await _getSetting(_activeProviderKey),
    );
    return loadConfigForProvider(provider);
  }

  static Future<AiProviderConfig> loadConfigForProvider(
    AiProviderKind provider,
  ) async {
    final definition = AiProviderCatalog.of(provider);
    final apiKey = await _getApiKey(provider) ?? '';
    final model =
        await _getSetting(_modelSettingKey(provider)) ??
        definition.defaultModel;
    final baseUrl = definition.supportsCustomBaseUrl
        ? (await _getSetting(_baseUrlSettingKey(provider))) ??
              definition.defaultBaseUrl
        : definition.defaultBaseUrl;

    return AiProviderConfig(
      provider: provider,
      apiKey: apiKey,
      model: model,
      baseUrl: baseUrl,
    );
  }

  static Future<void> saveConfig(AiProviderConfig config) async {
    await _saveSetting(
      _activeProviderKey,
      config.definition.id,
      description: 'Active AI provider',
    );
    await _saveSetting(
      _modelSettingKey(config.provider),
      config.model.trim(),
      description: '${config.definition.displayName} model',
    );
    if (config.definition.supportsCustomBaseUrl) {
      await _saveSetting(
        _baseUrlSettingKey(config.provider),
        config.resolvedBaseUrl,
        description: '${config.definition.displayName} base URL',
      );
    }
    if (config.definition.requiresApiKey || config.apiKey.trim().isNotEmpty) {
      await _saveSetting(
        _apiKeySettingKey(config.provider),
        config.apiKey.trim(),
        description: '${config.definition.displayName} API key',
      );
      if (config.provider == AiProviderKind.gemini) {
        await _saveSetting(
          _legacyGeminiKey,
          config.apiKey.trim(),
          description: 'Legacy Gemini API key',
        );
      }
    }
  }

  static Future<void> saveApiKey(String key) async {
    final current = await loadConfig();
    await saveConfig(current.copyWith(apiKey: key));
  }

  static Future<bool> isConfigured() async {
    final config = await loadConfig();
    return config.isComplete;
  }

  static Future<bool> testApiKey(String key) async {
    final current = await loadConfig();
    return testConfig(current.copyWith(apiKey: key));
  }

  static Future<bool> testConfig(AiProviderConfig config) async {
    if (!config.isComplete) return false;

    try {
      await _ensureProviderReachable(config);
      switch (config.provider) {
        case AiProviderKind.gemini:
          return await _testGemini(config);
        case AiProviderKind.claude:
          return await _testClaude(config);
        case AiProviderKind.ollama:
          return await _testOllama(config);
        case AiProviderKind.openai:
        case AiProviderKind.deepseek:
        case AiProviderKind.grok:
        case AiProviderKind.mistral:
        case AiProviderKind.openrouter:
          return await _testOpenAiCompatible(config);
      }
    } catch (_) {
      return false;
    }
  }

  static (String, String?) _extractThinkTags(String text) {
    final thinkRegex = RegExp(r'<think>(.*?)</think>', dotAll: true);
    final match = thinkRegex.firstMatch(text);
    if (match != null) {
      final reasoning = match.group(1)?.trim();
      final cleanText = text.replaceAll(thinkRegex, '').trim();
      return (cleanText, reasoning);
    }
    return (text, null);
  }

  static String _buildToolExecutionSummary(List<String> toolResults, {String? defaultReasoning}) {
    if (toolResults.isEmpty) {
      if (defaultReasoning != null && defaultReasoning.trim().isNotEmpty) {
        return defaultReasoning.trim();
      }
      return 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
    }

    final messages = <String>[];
    for (final raw in toolResults) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          if (decoded['message'] != null && decoded['message'].toString().trim().isNotEmpty) {
            messages.add(decoded['message'].toString().trim());
          } else if (decoded['error'] != null && decoded['error'].toString().trim().isNotEmpty) {
            messages.add('ข้อผิดพลาด: ${decoded['error']}');
          } else if (decoded['status'] == 'success') {
            messages.add('ดำเนินการบันทึกข้อมูลเรียบร้อยแล้ว');
          }
        }
      } catch (_) {}
    }

    if (messages.isEmpty) {
      if (defaultReasoning != null && defaultReasoning.trim().isNotEmpty) {
        return defaultReasoning.trim();
      }
      return 'ดำเนินการตามคำสั่งในระบบเรียบร้อยแล้วครับ';
    }

    return 'ดำเนินการเรียบร้อยแล้วครับ:\n\n' + messages.map((m) => '✅ $m').join('\n');
  }

  static String _describeToolCall(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'query_database':
        final sql = args['sql']?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        if (sql.isNotEmpty) {
          final preview = sql.length > 50 ? '${sql.substring(0, 50)}...' : sql;
          return 'ค้นหาในฐานข้อมูล: $preview';
        }
        return 'ค้นหาข้อมูลในฐานข้อมูล MASAPP';
      case 'get_available_tables':
        return 'ตรวจสอบตารางข้อมูลทั้งหมดในระบบ';
      case 'get_table_schema':
        final table = args['table_name'] ?? '';
        return 'ตรวจสอบโครงสร้างตาราง $table';
      case 'search_vector_knowledge':
        final q = args['query'] ?? '';
        return 'ค้นหาคู่มือ & องค์ความรู้ RAG "$q"';
      case 'extract_document_text':
      case 'read_document_text':
        final path = args['file_path'] ?? '';
        return 'สกัดและอ่านข้อความจากเอกสาร ($path)';
      case 'find_machine_assets':
        final id = args['machine_identifier'] ?? '';
        return 'ค้นหาไฟล์เอกสาร/คู่มือของเครื่อง $id';
      case 'manage_machine_assets':
      case 'attach_machine_document':
        final action = args['action'] ?? '';
        final id = args['machine_identifier'] ?? args['machine_no'] ?? '';
        final file = args['file_name'] ?? '';
        return 'แนบ/จัดการเอกสารเครื่องจักร $id ($action $file)'.trim();
      case 'manage_machines':
      case 'register_machines':
        final action = args['action'] ?? '';
        final id = args['machine_identifier'] ?? args['machine_no'] ?? '';
        return 'จัดการ/ตรวจสอบข้อมูลเครื่องจักร ($action $id)'.trim();
      case 'manage_work_orders':
      case 'create_work_order':
        final action = args['action'] ?? '';
        final id = args['wo_identifier'] ?? args['machine_identifier'] ?? '';
        return 'ตรวจสอบ/จัดการใบแจ้งซ่อม ($action $id)'.trim();
      case 'manage_pm_plans':
      case 'create_pm_plans':
        final action = args['action'] ?? '';
        final plan = args['plan_identifier'] ?? args['machine_identifier'] ?? '';
        return 'ตรวจสอบแผน PM/AM ($action $plan)'.trim();
      case 'manage_pm_schedules':
        final action = args['action'] ?? '';
        final plan = args['plan_identifier'] ?? '';
        return 'ตรวจสอบตารางงานบำรุงรักษา ($action $plan)'.trim();
      case 'manage_spare_parts':
      case 'register_spare_parts':
        final action = args['action'] ?? '';
        final part = args['part_identifier'] ?? args['part_name'] ?? '';
        return 'ตรวจสอบข้อมูลสต็อกอะไหล่ ($action $part)'.trim();
      case 'manage_tools':
        final action = args['action'] ?? '';
        final tool = args['tool_identifier'] ?? args['tool_name'] ?? '';
        return 'ตรวจสอบอุปกรณ์และเครื่องมือช่าง ($action $tool)'.trim();
      case 'manage_oee_logs':
        final action = args['action'] ?? '';
        return 'คำนวณ/ตรวจสอบสถิติ OEE ($action)';
      case 'manage_technicians':
        final action = args['action'] ?? '';
        final tech = args['full_name'] ?? args['technician_identifier'] ?? '';
        return 'จัดการข้อมูลช่าง/บุคลากร ($action $tech)'.trim();
      case 'manage_work_processes':
      case 'import_work_processes':
      case 'manage_sop_steps':
        final action = args['action'] ?? '';
        final mc = args['machine_identifier'] ?? args['process_no'] ?? '';
        return 'จัดการขั้นตอนการทำงาน SOP/JSA ($action $mc)'.trim();
      case 'manage_work_permits':
        final action = args['action'] ?? '';
        final id = args['permit_identifier'] ?? '';
        return 'ตรวจสอบใบอนุญาตทำงาน Work Permit ($action $id)'.trim();
      case 'manage_contractors':
        final action = args['action'] ?? '';
        final name = args['contractor_identifier'] ?? '';
        return 'ตรวจสอบข้อมูลผู้รับเหมา ($action $name)'.trim();
      case 'manage_locations':
        final action = args['action'] ?? '';
        return 'ตรวจสอบผังโรงงานและตำแหน่งเครื่อง ($action)';
      case 'external_web_search':
        final q = args['query'] ?? '';
        return 'ค้นหาข้อมูลภายนอกจากอินเทอร์เน็ต: $q';
      case 'external_image_search':
        final q = args['query'] ?? '';
        return 'ค้นหารูปภาพที่เกี่ยวข้อง: $q';
      case 'generate_chart':
      case 'create_chart':
      case 'render_chart':
        final type = args['chart_type'] ?? 'bar';
        final title = args['title'] ?? 'กราฟ';
        return 'กำลังสร้างกราฟ: $title ($type)';
      case 'subagent_query_database':
      case 'query_database_chunked':
      case 'subagent_batch_query':
        final desc = args['task_description'] ?? 'ดึงข้อมูลชุดใหญ่';
        return '🤖 Sub-agent กำลังช่วยแบ่งดึงข้อมูล: $desc';
      case 'generate_presentation_slides':
      case 'create_presentation':
      case 'build_presentation_deck':
      case 'export_slides_pdf':
        final title = args['title'] ?? 'สไลด์นำเสนอ';
        return '📽️ กำลังสร้างสไลด์นำเสนอและส่งออก PDF แนวนอน: $title';
      case 'synthesize_presentation_data':
        return '🤖 Sub-agents กำลังสังเคราะห์ข้อมูลข้ามทุกมิติสำหรับสไลด์นำเสนอ...';
      case 'manage_line_balancing':
      case 'create_production_line':
      case 'generate_line_balancing':
      case 'update_line_balancing':
      case 'manage_production_lines':
        final lname = args['line_name'] ?? 'สายการผลิต';
        final count = (args['stations'] as List?)?.length ?? 0;
        return '📐 กำลังจัดผัง Line Balancing และเชื่อมโยงเครื่องจักร: $lname ($count สถานี)';
      default:
        return 'เรียกใช้เครื่องมือ: $name';
    }
  }

  /// Window Cut Prevention & Context Budgeting:
  /// Preserves recent conversation flow while preventing token explosion and context dilution.
  static List<AiConversationMessage> _optimizeHistory(
    List<AiConversationMessage> history, {
    int maxMessages = 16,
    int maxTotalChars = 24000,
  }) {
    if (history.isEmpty) return const [];

    final recent = history.length > maxMessages
        ? history.sublist(history.length - maxMessages)
        : List<AiConversationMessage>.from(history);

    int currentChars = recent.fold(0, (sum, m) => sum + m.content.length);
    if (currentChars > maxTotalChars) {
      final optimized = <AiConversationMessage>[];
      final protectedCount = 4.clamp(0, recent.length);
      final startIndex = recent.length - protectedCount;

      for (int i = 0; i < recent.length; i++) {
        final msg = recent[i];
        if (i >= startIndex) {
          optimized.add(msg);
        } else {
          if (msg.content.length > 1000) {
            final truncated = '${msg.content.substring(0, 800)}\n...(ย่อเนื้อหาประวัติการสนทนา)...';
            optimized.add(AiConversationMessage(role: msg.role, content: truncated));
          } else {
            optimized.add(msg);
          }
        }
      }
      return optimized;
    }

    return recent;
  }

  static Future<AiChatResult> chat({
    AiProviderConfig? config,
    required List<AiConversationMessage> history,
    required String userMessage,
    List<AiAttachment> attachments = const [],
    List<Uint8List> imageBytesList = const [],
    void Function(String reasoningStep)? onReasoningStep,
    void Function(String reasoningChunk)? onReasoningChunk,
  }) async {
    final effectiveConfig = config ?? await loadConfig();
    await _ensureProviderReachable(effectiveConfig);

    final optimizedHistory = _optimizeHistory(history);

    switch (effectiveConfig.provider) {
      case AiProviderKind.gemini:
        return _chatWithGemini(
          effectiveConfig,
          optimizedHistory,
          userMessage,
          attachments: attachments,
          imageBytesList: imageBytesList,
          onReasoningStep: onReasoningStep,
          onReasoningChunk: onReasoningChunk,
        );
      case AiProviderKind.claude:
        return _chatWithClaude(
          effectiveConfig,
          optimizedHistory,
          userMessage,
          attachments: attachments,
          imageBytesList: imageBytesList,
          onReasoningStep: onReasoningStep,
          onReasoningChunk: onReasoningChunk,
        );
      case AiProviderKind.ollama:
        return _chatWithOllama(
          effectiveConfig,
          optimizedHistory,
          userMessage,
          onReasoningStep: onReasoningStep,
          onReasoningChunk: onReasoningChunk,
        );
      case AiProviderKind.openai:
      case AiProviderKind.deepseek:
      case AiProviderKind.grok:
      case AiProviderKind.mistral:
      case AiProviderKind.openrouter:
        return _chatWithOpenAiCompatible(
          effectiveConfig,
          optimizedHistory,
          userMessage,
          attachments: attachments,
          imageBytesList: imageBytesList,
          onReasoningStep: onReasoningStep,
          onReasoningChunk: onReasoningChunk,
        );
    }
  }

  static Future<String> _buildDynamicSystemInstruction() async {
    final buffer = StringBuffer(_systemInstruction);
    try {
      // 0. Organization & Factory Context
      final orgRows = await DbHelper.query(
        "SELECT setting_key, setting_value FROM app_settings WHERE setting_key LIKE 'org_%'",
      );
      final orgSettings = <String, String>{};
      for (final r in orgRows) {
        final k = r['setting_key']?.toString();
        final v = r['setting_value']?.toString();
        if (k != null && v != null) orgSettings[k] = v;
      }
      final orgName = orgSettings['org_name']?.trim().isNotEmpty == true
          ? orgSettings['org_name']!.trim()
          : '';
      final orgPlant = orgSettings['org_plant']?.trim().isNotEmpty == true
          ? orgSettings['org_plant']!.trim()
          : '';
      final orgDept = orgSettings['org_department']?.trim().isNotEmpty == true
          ? orgSettings['org_department']!.trim()
          : 'หน่วยงานซ่อมบำรุงและวิศวกรรม (Maintenance & Engineering)';
      final orgBusinessType = orgSettings['org_business_type']?.trim().isNotEmpty == true
          ? orgSettings['org_business_type']!.trim()
          : '';
      final orgAiContext = orgSettings['org_ai_context']?.trim() ?? '';

      if (orgName.isNotEmpty || orgBusinessType.isNotEmpty || orgAiContext.isNotEmpty) {
        buffer.writeln('\n\n=== FACTORY & ORGANIZATION DOMAIN CONTEXT ===');
        if (orgName.isNotEmpty) buffer.writeln('- Company / Organization: $orgName');
        if (orgPlant.isNotEmpty) buffer.writeln('- Plant / Location: $orgPlant');
        if (orgDept.isNotEmpty) buffer.writeln('- Primary Department: $orgDept');
        if (orgBusinessType.isNotEmpty) buffer.writeln('- Core Manufacturing & Business: $orgBusinessType');
        if (orgAiContext.isNotEmpty) {
          buffer.writeln('- Factory Context & Details: $orgAiContext');
        }
        buffer.writeln('FACTORY SCOPE & DOMAIN KNOWLEDGE: You are the dedicated Smart Maintenance & Industrial Engineering AI for this factory. When analyzing machines, production lines, maintenance orders, spare parts, and Lean VSM process steps, strictly align with this factory domain.');
      }

      // 1. Registered Machines
      final machines = await DbHelper.query(
        'SELECT machine_no, machine_name, brand, model FROM machines WHERE is_active = 1 ORDER BY machine_no ASC LIMIT 100',
      );
      if (machines.isNotEmpty) {
        buffer.writeln('\n\nCURRENT MASAPP REGISTERED MACHINES DIRECTORY (Total ${machines.length} machines):');
        for (final m in machines) {
          final no = m['machine_no']?.toString().trim() ?? '';
          final name = m['machine_name']?.toString().trim() ?? '';
          final brand = m['brand']?.toString().trim() ?? '';
          final model = m['model']?.toString().trim() ?? '';
          final extra = [if (brand.isNotEmpty) brand, if (model.isNotEmpty) model].join(' ');
          final extraStr = extra.isNotEmpty ? ' ($extra)' : '';
          buffer.writeln('- $no: $name$extraStr');
        }
        buffer.writeln('INSTRUCTION: Always resolve colloquial machine names (e.g. from registered directory) to their machine_no. NEVER ask the user to provide machine code!');
      }

      // 2. Spare Parts Overview
      final parts = await DbHelper.query('''
        SELECT sp.part_code, sp.part_name, sp.category, inv.quantity_on_hand
        FROM spare_parts sp
        LEFT JOIN spare_parts_inventory inv ON sp.part_id = inv.part_id
        WHERE sp.is_active = 1
        ORDER BY sp.part_code ASC LIMIT 60
      ''');
      if (parts.isNotEmpty) {
        buffer.writeln('\nSPARE PARTS & WAREHOUSE DIRECTORY (Total ${parts.length} items):');
        for (final p in parts) {
          final code = p['part_code'] ?? '';
          final name = p['part_name'] ?? '';
          final cat = p['category'] ?? '-';
          final qty = p['quantity_on_hand'] ?? 0;
          buffer.writeln('- $code: $name ($cat, คงเหลือ: $qty)');
        }
      }

      // 3. Tools & Equipment Overview
      final tools = await DbHelper.query(
        'SELECT tool_code, tool_name, status FROM tools WHERE is_active = 1 ORDER BY tool_code ASC LIMIT 40',
      );
      if (tools.isNotEmpty) {
        buffer.writeln('\nTOOLS & EQUIPMENT DIRECTORY:');
        for (final t in tools) {
          final code = t['tool_code'] ?? '';
          final name = t['tool_name'] ?? '';
          final status = t['status'] ?? 'available';
          buffer.writeln('- $code: $name (สถานะ: $status)');
        }
      }

      // 4. Active Work Orders
      final openWos = await DbHelper.query('''
        SELECT wo_no, title, priority, status FROM work_orders
        WHERE status IN ('open', 'in_progress', 'pending')
        ORDER BY created_at DESC LIMIT 15
      ''');
      if (openWos.isNotEmpty) {
        buffer.writeln('\nACTIVE/OPEN WORK ORDERS:');
        for (final wo in openWos) {
          final no = wo['wo_no'] ?? '';
          final title = wo['title'] ?? '';
          final prio = wo['priority'] ?? 'medium';
          final status = wo['status'] ?? 'open';
          buffer.writeln('- $no: $title [สถานะ: $status, ความเร่งด่วน: $prio]');
        }
      }

      // 5. Work Processes & Lean Analysis
      final wps = await DbHelper.query(
        'SELECT process_no, title, method_type FROM work_processes ORDER BY created_at DESC LIMIT 15',
      );
      if (wps.isNotEmpty) {
        buffer.writeln('\nREGISTERED WORK PROCESSES & LEAN FLOWS:');
        for (final wp in wps) {
          final pNo = wp['process_no'] ?? '';
          final title = wp['title'] ?? '';
          final method = wp['method_type'] == 'improved' ? 'ฉบับปรับปรุง' : 'ฉบับปัจจุบัน';
          buffer.writeln('- $pNo: $title ($method)');
        }
      }

      // 6. Registered Technicians & Workforce
      final techRows = await DbHelper.query('''
        SELECT u.user_id, u.employee_no, u.full_name, u.role, u.phone, u.email, d.dept_name
        FROM users u
        LEFT JOIN departments d ON d.dept_id = u.dept_id
        WHERE u.is_active = 1
        ORDER BY u.role, u.full_name
        LIMIT 50
      ''');
      if (techRows.isNotEmpty) {
        buffer.writeln('\nREGISTERED TECHNICIANS & WORKFORCE DIRECTORY (Total ${techRows.length} members):');
        for (final t in techRows) {
          final uid = t['user_id'].toString();
          final empNo = t['employee_no']?.toString() ?? '-';
          final name = t['full_name']?.toString() ?? '';
          final role = t['role']?.toString() ?? 'technician';
          final dept = t['dept_name']?.toString() ?? 'ซ่อมบำรุง';

          final sRows = await DbHelper.query(
            'SELECT skill_name, proficiency_level FROM technician_skills WHERE technician_id = @id',
            params: {'id': uid},
          );
          final skillsStr = sRows.map((s) => '${s['skill_name']}(${s['proficiency_level']})').join(', ');
          final skillPart = skillsStr.isNotEmpty ? ' | ทักษะ: $skillsStr' : '';
          buffer.writeln('- $empNo: $name ($role, $dept)$skillPart');
        }
        buffer.writeln('INSTRUCTION: You can manage, query, and recommend technicians. To register a new technician, call manage_technicians with action: "create_technician". When the user asks "เพิ่มช่างให้หน่อย" without details, prompt them for name, role, department, and skills, or accept whatever parameters they provide.');
      }

      // 7. Registered Outsource Contractors & Suppliers
      final suppRows = await DbHelper.query('''
        SELECT supplier_code, name, contact_name, phone, service_scope, vendor_type
        FROM suppliers
        WHERE is_active = 1
        ORDER BY name
        LIMIT 30
      ''');
      if (suppRows.isNotEmpty) {
        buffer.writeln('\nREGISTERED CONTRACTORS & OUTSOURCE SUPPLIERS DIRECTORY (Total ${suppRows.length} vendors):');
        for (final s in suppRows) {
          final code = s['supplier_code']?.toString() ?? '';
          final sName = s['name']?.toString() ?? '';
          final scope = s['service_scope']?.toString() ?? 'บริการซ่อมบำรุง';
          final tel = s['phone']?.toString() ?? '';
          final telPart = tel.isNotEmpty ? ' (โทร: $tel)' : '';
          buffer.writeln('- $code: $sName$telPart | งาน: $scope');
        }
        buffer.writeln('INSTRUCTION: You can manage, query, and register outsource contractors using manage_contractors (action: create_contractor). When user asks "เพิ่มทะเบียนผู้รับเหมาให้หน่อย", you can create a contractor or prompt for details.');
      }
    } catch (_) {}
    return buffer.toString();
  }

  static Future<AiChatResult> _chatWithGemini(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage, {
    List<AiAttachment> attachments = const [],
    List<Uint8List> imageBytesList = const [],
    void Function(String reasoningStep)? onReasoningStep,
    void Function(String reasoningChunk)? onReasoningChunk,
  }) async {
    final steps = <String>[];
    void addStep(String s) {
      if (!steps.contains(s)) {
        steps.add(s);
        onReasoningStep?.call(s);
      }
    }

    addStep('กำลังวิเคราะห์คำถามและบริบท...');

    final dynamicSystemInstruction = await _buildDynamicSystemInstruction();

    final model = GenerativeModel(
      model: config.model,
      apiKey: config.apiKey,
      systemInstruction: Content.system(dynamicSystemInstruction),
      tools: [
        Tool(
          functionDeclarations: [
            _manageMachineAssetsTool,
            _manageMachinesTool,
            _manageLocationsTool,
            _managePmPlansTool,
            _managePmSchedulesTool,
            _manageWorkOrdersTool,
            _manageContractorsTool,
            _manageWorkPermitsTool,
            _manageSparePartsTool,
            _manageToolsTool,
            _manageOeeLogsTool,
            _manageTechniciansTool,
            _manageWorkProcessesTool,
            _registerMachinesTool,
            _createPmPlansTool,
            _registerSparePartsTool,
            _createWorkOrderTool,
            _searchVectorKnowledgeTool,
            _extractDocumentTextTool,
            _queryDbTool,
            _getTablesTool,
            _getSchemaTool,
            _findMachineAssetsTool,
            _externalWebSearchTool,
            _externalImageSearchTool,
            _generateChartTool,
            _subagentQueryDbTool,
            _generatePresentationSlidesTool,
            _manageLineBalancingTool,
          ],
        ),
      ],
      generationConfig: GenerationConfig(
        temperature: 0.3,
        maxOutputTokens: 8192,
      ),
    );

    final geminiHistory = history.map((message) {
      if (message.role == 'assistant') {
        return Content.model([TextPart(message.content)]);
      }
      return Content.text(message.content);
    }).toList();

    final session = model.startChat(history: geminiHistory);
    final userParts = <Part>[TextPart(userMessage)];
    for (final att in attachments) {
      userParts.add(DataPart(att.mimeType, att.bytes));
    }
    for (final imgBytes in imageBytesList) {
      userParts.add(DataPart('image/png', imgBytes));
    }

    Future<GenerateContentResponse> sendWithRetry(Content content) async {
      int attempts = 0;
      while (true) {
        attempts++;
        try {
          return await session.sendMessage(content);
        } catch (e) {
          final errStr = e.toString();
          final isRateLimit = errStr.contains('429') ||
              errStr.contains('ResourceExhausted') ||
              errStr.contains('RESOURCE_EXHAUSTED') ||
              errStr.contains('rate limit') ||
              errStr.contains('Quota exceeded');
          if (isRateLimit && attempts <= 3) {
            final delaySec = attempts * 3;
            addStep('กำลังรอระบบ AI สักครู่ ($delaySec วินาที) เนื่องจากมีคำขอใช้งานสูง...');
            await Future.delayed(Duration(seconds: delaySec));
            continue;
          }
          rethrow;
        }
      }
    }

    var response = await sendWithRetry(
      userParts.length > 1 ? Content.multi(userParts) : Content.text(userMessage),
    );

    final executedToolOutputs = <String>[];
    for (var i = 0; i < 25 && response.functionCalls.isNotEmpty; i++) {
      final functionResponses = <FunctionResponse>[];

      for (final call in response.functionCalls) {
        final toolArgs = call.args.cast<String, dynamic>();
        addStep(_describeToolCall(call.name, toolArgs));

        final result = await AiToolHandler.handleToolCall(
          call.name,
          toolArgs,
          onProgress: addStep,
        );
        executedToolOutputs.add(result);
        functionResponses.add(FunctionResponse(call.name, {'output': result}));
      }

      addStep('กำลังประมวลผลข้อมูลและเตรียมคำตอบ...');
      // Subtle throttle delay to prevent bursting API
      await Future.delayed(const Duration(milliseconds: 500));
      response = await sendWithRetry(
        Content.functionResponses(functionResponses),
      );
    }

    var (cleanText, extractedReasoning) = _extractThinkTags(response.text ?? '');
    if (cleanText.isEmpty && executedToolOutputs.isNotEmpty) {
      cleanText = _buildToolExecutionSummary(executedToolOutputs, defaultReasoning: extractedReasoning);
    } else if (cleanText.isEmpty && extractedReasoning != null && extractedReasoning.isNotEmpty) {
      cleanText = extractedReasoning;
    }
    final finalText = cleanText.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : cleanText;

    return AiChatResult(
      text: finalText,
      reasoningSteps: steps,
      reasoningContent: extractedReasoning,
    );
  }

  static Future<AiChatResult> _chatWithOpenAiCompatible(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage, {
    List<AiAttachment> attachments = const [],
    List<Uint8List> imageBytesList = const [],
    void Function(String reasoningStep)? onReasoningStep,
    void Function(String reasoningChunk)? onReasoningChunk,
  }) async {
    final steps = <String>[];
    void addStep(String s) {
      if (!steps.contains(s)) {
        steps.add(s);
        onReasoningStep?.call(s);
      }
    }

    final reasoningBuffer = StringBuffer();
    addStep('กำลังวิเคราะห์คำถามและบริบท...');

    final dynamicSystemInstruction = await _buildDynamicSystemInstruction();

    final hasVisuals = attachments.isNotEmpty || imageBytesList.isNotEmpty;
    final dynamic userContent;
    if (!hasVisuals) {
      userContent = userMessage;
    } else {
      userContent = <Map<String, dynamic>>[
        {'type': 'text', 'text': userMessage},
        ...attachments
            .where((a) => a.mimeType.startsWith('image/'))
            .map((a) => {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:${a.mimeType};base64,${base64Encode(a.bytes)}',
                  },
                }),
        ...imageBytesList.map((b) => {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/png;base64,${base64Encode(b)}',
              },
            }),
      ];
    }

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': dynamicSystemInstruction},
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userContent},
    ];

    final executedToolOutputs = <String>[];

    for (var i = 0; i < 25; i++) {
      final headers = <String, String>{
        'Authorization': 'Bearer ${config.apiKey}',
      };
      final isOpenRouter = config.provider == AiProviderKind.openrouter ||
          config.resolvedBaseUrl.contains('openrouter.ai');
      if (isOpenRouter) {
        headers['HTTP-Referer'] = 'https://masapp.local';
        headers['X-Title'] = 'MASAPP Maintenance AI';
      }

      final body = <String, dynamic>{
        'model': config.model,
        'messages': messages,
        'tools': _openAiTools,
        'tool_choice': 'auto',
        'temperature': 0.3,
        'max_tokens': 8192,
      };

      if (isOpenRouter) {
        body['reasoning'] = {
          'max_tokens': 4096,
        };
      }

      final json = await _postJson(
        _normalizeBaseUrl(config.resolvedBaseUrl, '/chat/completions'),
        headers: headers,
        body: body,
      );

      final choices = (json['choices'] as List?) ?? const [];
      if (choices.isEmpty) {
        throw Exception('No choices returned from AI provider');
      }

      final choice = choices.first as Map<String, dynamic>;
      final message =
          (choice['message'] as Map?)?.cast<String, dynamic>() ?? {};
      final toolCalls = (message['tool_calls'] as List?) ?? const [];

      var rawReasoning = message['reasoning_content']?.toString() ??
          message['reasoning']?.toString();
      if ((rawReasoning == null || rawReasoning.isEmpty) &&
          message['reasoning_details'] is List) {
        final details = message['reasoning_details'] as List;
        rawReasoning = details
            .map((d) => d is Map
                ? (d['text'] ?? d['content'] ?? d.toString())
                : d.toString())
            .join('\n');
      }

      if (rawReasoning != null && rawReasoning.isNotEmpty) {
        reasoningBuffer.write(rawReasoning);
        onReasoningChunk?.call(rawReasoning);
      }

      if (toolCalls.isEmpty) {
        var text = _extractOpenAiContent(message['content']);
        var (cleanText, extractedReasoning) = _extractThinkTags(text);
        if (extractedReasoning != null && extractedReasoning.isNotEmpty) {
          reasoningBuffer.write(extractedReasoning);
        }
        if (cleanText.isEmpty && executedToolOutputs.isNotEmpty) {
          cleanText = _buildToolExecutionSummary(executedToolOutputs, defaultReasoning: reasoningBuffer.toString());
        } else if (cleanText.isEmpty && reasoningBuffer.isNotEmpty) {
          cleanText = reasoningBuffer.toString();
        }
        final finalText = cleanText.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : cleanText;
        return AiChatResult(
          text: finalText,
          reasoningSteps: steps,
          reasoningContent: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        );
      }

      messages.add({
        'role': 'assistant',
        'content': message['content'],
        'tool_calls': toolCalls,
      });

      for (final rawCall in toolCalls.cast<Map<String, dynamic>>()) {
        final function =
            (rawCall['function'] as Map?)?.cast<String, dynamic>() ?? {};
        final args = _decodeArguments(function['arguments']);
        final toolName = function['name']?.toString() ?? '';
        addStep(_describeToolCall(toolName, args));

        final result = await AiToolHandler.handleToolCall(
          toolName,
          args,
          onProgress: addStep,
        );
        executedToolOutputs.add(result);
        messages.add({
          'role': 'tool',
          'tool_call_id': rawCall['id'],
          'content': result,
        });
      }
      addStep('กำลังประมวลผลข้อมูลและเตรียมคำตอบ...');
    }

    final fallbackText = _buildToolExecutionSummary(executedToolOutputs, defaultReasoning: reasoningBuffer.toString());
    return AiChatResult(
      text: fallbackText,
      reasoningSteps: steps,
      reasoningContent: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
    );
  }

  static Future<AiChatResult> _chatWithClaude(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage, {
    List<AiAttachment> attachments = const [],
    List<Uint8List> imageBytesList = const [],
    void Function(String reasoningStep)? onReasoningStep,
    void Function(String reasoningChunk)? onReasoningChunk,
  }) async {
    final steps = <String>[];
    void addStep(String s) {
      if (!steps.contains(s)) {
        steps.add(s);
        onReasoningStep?.call(s);
      }
    }

    final reasoningBuffer = StringBuffer();
    addStep('กำลังวิเคราะห์คำถามและบริบท...');

    final dynamicSystemInstruction = await _buildDynamicSystemInstruction();

    final hasVisuals = attachments.isNotEmpty || imageBytesList.isNotEmpty;
    final dynamic userContent;
    if (!hasVisuals) {
      userContent = userMessage;
    } else {
      userContent = <Map<String, dynamic>>[
        {'type': 'text', 'text': userMessage},
        ...attachments.map((a) {
          if (a.mimeType.startsWith('image/')) {
            return {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': a.mimeType,
                'data': base64Encode(a.bytes),
              },
            };
          } else if (a.mimeType == 'application/pdf') {
            return {
              'type': 'document',
              'source': {
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': base64Encode(a.bytes),
              },
            };
          }
          return {'type': 'text', 'text': '(เอกสารแนบ: ${a.fileName})'};
        }),
        ...imageBytesList.map((b) => {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/png',
                'data': base64Encode(b),
              },
            }),
      ];
    }

    final messages = <Map<String, dynamic>>[
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userContent},
    ];

    final executedToolOutputs = <String>[];

    for (var i = 0; i < 25; i++) {
      final json = await _postJson(
        _normalizeBaseUrl(config.resolvedBaseUrl, '/messages'),
        headers: {
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: {
          'model': config.model,
          'system': dynamicSystemInstruction,
          'messages': messages,
          'tools': _anthropicTools,
          'temperature': 0.3,
          'max_tokens': 8192,
        },
      );

      final content = (json['content'] as List?) ?? const [];
      final textParts = <String>[];
      final toolResults = <Map<String, dynamic>>[];

      for (final block in content.cast<Map<String, dynamic>>()) {
        final type = block['type']?.toString() ?? '';
        if (type == 'thinking') {
          final thinkingText = block['thinking']?.toString() ?? '';
          if (thinkingText.isNotEmpty) {
            reasoningBuffer.write(thinkingText);
            onReasoningChunk?.call(thinkingText);
          }
          continue;
        }
        if (type == 'text') {
          final text = block['text']?.toString() ?? '';
          if (text.isNotEmpty) textParts.add(text);
          continue;
        }
        if (type == 'tool_use') {
          final toolName = block['name']?.toString() ?? '';
          final toolArgs = (block['input'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
          addStep(_describeToolCall(toolName, toolArgs));

          final result = await AiToolHandler.handleToolCall(
            toolName,
            toolArgs,
            onProgress: addStep,
          );
          executedToolOutputs.add(result);
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': block['id'],
            'content': result,
          });
        }
      }

      if (toolResults.isEmpty) {
        var text = textParts.join('\n').trim();
        var (cleanText, extractedReasoning) = _extractThinkTags(text);
        if (extractedReasoning != null && extractedReasoning.isNotEmpty) {
          reasoningBuffer.write(extractedReasoning);
        }
        if (cleanText.isEmpty && executedToolOutputs.isNotEmpty) {
          cleanText = _buildToolExecutionSummary(executedToolOutputs, defaultReasoning: reasoningBuffer.toString());
        } else if (cleanText.isEmpty && reasoningBuffer.isNotEmpty) {
          cleanText = reasoningBuffer.toString();
        }
        final finalText = cleanText.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : cleanText;
        return AiChatResult(
          text: finalText,
          reasoningSteps: steps,
          reasoningContent: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        );
      }

      addStep('กำลังประมวลผลข้อมูลและเตรียมคำตอบ...');
      messages.add({'role': 'assistant', 'content': content});
      messages.add({'role': 'user', 'content': toolResults});
    }

    final fallbackText = _buildToolExecutionSummary(executedToolOutputs, defaultReasoning: reasoningBuffer.toString());
    return AiChatResult(
      text: fallbackText,
      reasoningSteps: steps,
      reasoningContent: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
    );
  }

  static Future<AiChatResult> _chatWithOllama(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage, {
    void Function(String reasoningStep)? onReasoningStep,
    void Function(String reasoningChunk)? onReasoningChunk,
  }) async {
    final steps = <String>[];
    void addStep(String s) {
      if (!steps.contains(s)) {
        steps.add(s);
        onReasoningStep?.call(s);
      }
    }

    final reasoningBuffer = StringBuffer();
    addStep('กำลังวิเคราะห์คำถามและบริบท...');

    final dynamicSystemInstruction = await _buildDynamicSystemInstruction();

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': dynamicSystemInstruction},
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userMessage},
    ];

    final executedToolOutputs = <String>[];

    for (var i = 0; i < 25; i++) {
      final headers = <String, String>{};
      if (config.apiKey.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
      }

      final json = await _postJson(
        _normalizeBaseUrl(config.resolvedBaseUrl, '/api/chat'),
        headers: headers,
        body: {
          'model': config.model,
          'messages': messages,
          'stream': false,
          'tools': _openAiTools,
        },
      );

      final message = (json['message'] as Map?)?.cast<String, dynamic>() ?? {};
      final toolCalls = (message['tool_calls'] as List?) ?? const [];

      final rawReasoning = message['reasoning_content']?.toString() ??
          message['reasoning']?.toString() ??
          '';
      if (rawReasoning.isNotEmpty) {
        reasoningBuffer.write(rawReasoning);
        onReasoningChunk?.call(rawReasoning);
      }

      if (toolCalls.isEmpty) {
        var text = message['content']?.toString().trim() ?? '';
        var (cleanText, extractedReasoning) = _extractThinkTags(text);
        if (extractedReasoning != null && extractedReasoning.isNotEmpty) {
          reasoningBuffer.write(extractedReasoning);
        }
        if (cleanText.isEmpty && executedToolOutputs.isNotEmpty) {
          cleanText = _buildToolExecutionSummary(executedToolOutputs, defaultReasoning: reasoningBuffer.toString());
        } else if (cleanText.isEmpty && reasoningBuffer.isNotEmpty) {
          cleanText = reasoningBuffer.toString();
        }
        final finalText = cleanText.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : cleanText;
        return AiChatResult(
          text: finalText,
          reasoningSteps: steps,
          reasoningContent: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
        );
      }

      messages.add({
        'role': 'assistant',
        'content': message['content'],
        'tool_calls': toolCalls,
      });

      for (final rawCall in toolCalls.cast<Map<String, dynamic>>()) {
        final function =
            (rawCall['function'] as Map?)?.cast<String, dynamic>() ?? {};
        final args = _decodeArguments(function['arguments']);
        final toolName = function['name']?.toString() ?? '';
        addStep(_describeToolCall(toolName, args));

        final result = await AiToolHandler.handleToolCall(
          toolName,
          args,
          onProgress: addStep,
        );
        executedToolOutputs.add(result);
        messages.add({
          'role': 'tool',
          'tool_call_id': rawCall['id'],
          'content': result,
        });
      }
      addStep('กำลังประมวลผลข้อมูลและเตรียมคำตอบ...');
    }

    final fallbackText = _buildToolExecutionSummary(executedToolOutputs, defaultReasoning: reasoningBuffer.toString());
    return AiChatResult(
      text: fallbackText,
      reasoningSteps: steps,
      reasoningContent: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
    );
  }

  static Future<bool> _testGemini(AiProviderConfig config) async {
    final model = GenerativeModel(
      model: config.model,
      apiKey: config.apiKey,
      generationConfig: GenerationConfig(maxOutputTokens: 10),
    );
    await model.generateContent([Content.text('ping')]);
    return true;
  }

  static Future<bool> _testOpenAiCompatible(AiProviderConfig config) async {
    final headers = <String, String>{
      'Authorization': 'Bearer ${config.apiKey}',
    };
    if (config.provider == AiProviderKind.openrouter ||
        config.resolvedBaseUrl.contains('openrouter.ai')) {
      headers['HTTP-Referer'] = 'https://masapp.local';
      headers['X-Title'] = 'MASAPP Maintenance AI';
    }

    await _postJson(
      _normalizeBaseUrl(config.resolvedBaseUrl, '/chat/completions'),
      headers: headers,
      body: {
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'max_tokens': 8,
      },
    );
    return true;
  }

  static Future<bool> _testClaude(AiProviderConfig config) async {
    await _postJson(
      _normalizeBaseUrl(config.resolvedBaseUrl, '/messages'),
      headers: {'x-api-key': config.apiKey, 'anthropic-version': '2023-06-01'},
      body: {
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'max_tokens': 8,
      },
    );
    return true;
  }

  static Future<bool> _testOllama(AiProviderConfig config) async {
    final headers = <String, String>{};
    if (config.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }
    await _postJson(
      _normalizeBaseUrl(config.resolvedBaseUrl, '/api/chat'),
      headers: headers,
      body: {
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': 'ping'},
        ],
        'stream': false,
      },
    );
    return true;
  }

  static Future<Map<String, dynamic>> _postJson(
    String url, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    final response = await http
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json', ...headers},
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Invalid response format');
  }

  static String _normalizeBaseUrl(String baseUrl, String suffix) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return '$trimmed$suffix';
  }

  static String _extractOpenAiContent(dynamic content) {
    if (content == null) return '';
    if (content is String) return content.trim();
    if (content is List) {
      return content
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((text) => text.isNotEmpty)
          .join('\n')
          .trim();
    }
    return content.toString().trim();
  }

  static Map<String, dynamic> _decodeArguments(dynamic rawArguments) {
    if (rawArguments is Map<String, dynamic>) return rawArguments;
    if (rawArguments is Map) return rawArguments.cast<String, dynamic>();
    if (rawArguments is String && rawArguments.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArguments);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        final repaired = _tryRepairJson(rawArguments);
        if (repaired != null) return repaired;
      }
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic>? _tryRepairJson(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    for (var attempt = 0; attempt < 50; attempt++) {
      try {
        final candidate = _closeJsonBrackets(trimmed);
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        final lastComma = trimmed.lastIndexOf(',');
        if (lastComma > 0) {
          trimmed = trimmed.substring(0, lastComma).trim();
        } else {
          break;
        }
      }
    }
    return null;
  }

  static String _closeJsonBrackets(String input) {
    var str = input.trim();
    final stack = <String>[];
    var inString = false;
    var isEscaped = false;

    for (var i = 0; i < str.length; i++) {
      final char = str[i];
      if (isEscaped) {
        isEscaped = false;
        continue;
      }
      if (char == '\\') {
        isEscaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (char == '{') {
          stack.add('}');
        } else if (char == '[') {
          stack.add(']');
        } else if (char == '}' || char == ']') {
          if (stack.isNotEmpty) stack.removeLast();
        }
      }
    }

    if (inString) {
      str += '"';
    }

    str = str.replaceAll(RegExp(r',\s*$'), '');

    while (stack.isNotEmpty) {
      str += stack.removeLast();
    }

    return str;
  }

  static String _extractError(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          return error['message']?.toString() ?? 'HTTP $statusCode';
        }
        if (error != null) return error.toString();
      }
    } catch (_) {}
    return 'HTTP $statusCode';
  }

  static Future<void> _ensureProviderReachable(AiProviderConfig config) async {
    final isCloudProvider = config.provider != AiProviderKind.ollama;
    final baseUrl = config.resolvedBaseUrl;

    if (baseUrl.isEmpty) {
      throw Exception('ยังไม่ได้ตั้งค่า Base URL ของ AI Provider');
    }

    final uri = Uri.tryParse(baseUrl);
    final host = uri?.host ?? '';
    if (host.isEmpty) {
      throw Exception('Base URL ของ AI Provider ไม่ถูกต้อง');
    }

    try {
      final results = await InternetAddress.lookup(host);
      if (results.isEmpty) {
        throw const SocketException('No address resolved');
      }
    } on SocketException {
      if (isCloudProvider) {
        throw Exception(
          'ไม่มีการเชื่อมต่ออินเทอร์เน็ต หรือไม่สามารถเข้าถึง ${config.definition.displayName} ได้ในขณะนี้',
        );
      }
      throw Exception(
        'ไม่สามารถเชื่อมต่อ ${config.definition.displayName} ได้ กรุณาตรวจสอบว่า service กำลังรันอยู่',
      );
    }
  }

  static String _apiKeySettingKey(AiProviderKind provider) {
    return 'ai_api_key_${AiProviderCatalog.of(provider).id}';
  }

  static String _modelSettingKey(AiProviderKind provider) {
    return 'ai_model_${AiProviderCatalog.of(provider).id}';
  }

  static String _baseUrlSettingKey(AiProviderKind provider) {
    return 'ai_base_url_${AiProviderCatalog.of(provider).id}';
  }

  static Future<String?> _getApiKey(AiProviderKind provider) async {
    final key = await _getSetting(_apiKeySettingKey(provider));
    if ((key ?? '').isNotEmpty) return key;
    if (provider == AiProviderKind.gemini) {
      return _getSetting(_legacyGeminiKey);
    }
    return null;
  }

  static Future<String?> _getSetting(String key) async {
    try {
      final row = await DbHelper.queryOne(
        'SELECT setting_value FROM app_settings WHERE setting_key = @key',
        params: {'key': key},
      );
      return row?['setting_value']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveSetting(
    String key,
    String value, {
    String? description,
  }) async {
    await DbHelper.execute(
      '''INSERT INTO app_settings(setting_key, setting_value, description, updated_at)
         VALUES(@key, @value, @description, CURRENT_TIMESTAMP)
         ON CONFLICT(setting_key)
         DO UPDATE SET
           setting_value = excluded.setting_value,
           description = excluded.description,
           updated_at = excluded.updated_at''',
      params: {'key': key, 'value': value, 'description': description ?? ''},
    );
  }
}
