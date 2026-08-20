import 'dart:convert';
import 'dart:io';

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

class AiService {
  static const _activeProviderKey = 'ai_provider';
  static const _legacyGeminiKey = 'gemini_api_key';
  static const _requestTimeout = Duration(seconds: 30);

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

DATABASE ACTION & CRUD TOOLS (Insert, Update, Delete across all modules):
- Machines: Call `manage_machines` (action: insert / update / delete). Also supports bulk `machines` list for importing documents.
- Locations & Layout: Call `manage_locations` (action: create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position).
- PM/AM Master Plans: Call `manage_pm_plans` (action: create_plan, update_plan, delete_plan, add_task, delete_task).
- PM/AM Schedules: Call `manage_pm_schedules` (action: create_schedule, update_status, record_execution, delete_schedule).
- Work Orders & RCA: Call `manage_work_orders` (action: create_order, update_order, record_labor, record_rca, delete_order).
- Outsource Vendors / Contractors: Call `manage_contractors` (action: create_contractor, update_contractor, delete_contractor).
- Work Permits: Call `manage_work_permits` (action: create_permit, update_status, update_safety_check, delete_permit).
- Spare Parts & Inventory: Call `manage_spare_parts` (action: create_part, update_part, delete_part, record_transaction, link_machine).
- Tools & Equipment: Call `manage_tools` (action: create_tool, update_tool, delete_tool, record_transaction).
- OEE Logs: Call `manage_oee_logs` (action: record_log, update_log, delete_log).
- Technicians & Skills: Call `manage_technicians` (action: add_skill, update_skill, delete_skill, set_availability).

Start by greeting the user and asking how you can help with maintenance operations today.
''';

  static final _manageMachinesTool = FunctionDeclaration(
    'manage_machines',
    'Manage machine records (Insert, Update, Delete/Deactivate, and Specs) in MASAPP database. Supports bulk import array.',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'insert, update, delete'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No (e.g. "MC-01") or ID'),
        'machine_no': Schema(SchemaType.string, description: 'Unique machine code/ID'),
        'machine_name': Schema(SchemaType.string, description: 'Name of machine'),
        'asset_no': Schema(SchemaType.string, description: 'Asset tag number'),
        'brand': Schema(SchemaType.string, description: 'Brand/Manufacturer'),
        'model': Schema(SchemaType.string, description: 'Model'),
        'serial_no': Schema(SchemaType.string, description: 'Serial number'),
        'location': Schema(SchemaType.string, description: 'Installation area/room/line'),
        'status': Schema(SchemaType.string, description: 'normal, breakdown, pm, offline'),
        'notes': Schema(SchemaType.string, description: 'Additional remarks or specs summary'),
        'machines': Schema(
          SchemaType.array,
          items: Schema(
            SchemaType.object,
            properties: {
              'machine_no': Schema(SchemaType.string, description: 'Unique machine code/ID'),
              'machine_name': Schema(SchemaType.string, description: 'Machine name'),
              'brand': Schema(SchemaType.string),
              'model': Schema(SchemaType.string),
              'location': Schema(SchemaType.string),
              'status': Schema(SchemaType.string),
              'notes': Schema(SchemaType.string),
            },
            requiredProperties: ['machine_no'],
          ),
          description: 'Optional array of machine objects for bulk import',
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
        'layout_name': Schema(SchemaType.string, description: 'Name of the factory layout'),
        'zone_name': Schema(SchemaType.string, description: 'Name of the zone/area'),
        'zone_type': Schema(SchemaType.string, description: 'production, storage, maintenance, safety'),
        'machine_identifier': Schema(SchemaType.string, description: 'Machine code/No or ID'),
        'x_position': Schema(SchemaType.number, description: 'X coordinate on layout'),
        'y_position': Schema(SchemaType.number, description: 'Y coordinate on layout'),
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
    'Manage technician skill matrix and daily availability (add_skill, update_skill, delete_skill, set_availability).',
    Schema(
      SchemaType.object,
      properties: {
        'action': Schema(SchemaType.string, description: 'add_skill, update_skill, delete_skill, set_availability'),
        'technician_identifier': Schema(SchemaType.string, description: 'Technician username, name, or ID'),
        'skill_name': Schema(SchemaType.string, description: 'Skill/Competency name'),
        'proficiency_level': Schema(SchemaType.string, description: 'basic, intermediate, expert'),
        'certified': Schema(SchemaType.boolean, description: 'Whether certified'),
        'available_date': Schema(SchemaType.string, description: 'Availability date (YYYY-MM-DD)'),
        'available_hours': Schema(SchemaType.number, description: 'Available work hours (default 8)'),
        'reserved_hours': Schema(SchemaType.number, description: 'Reserved/Booked hours'),
      },
      requiredProperties: ['action', 'technician_identifier'],
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

  static final _openAiTools = [
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
            'machines': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'machine_no': {'type': 'string'},
                  'machine_name': {'type': 'string'},
                  'brand': {'type': 'string'},
                  'model': {'type': 'string'},
                  'location': {'type': 'string'},
                  'status': {'type': 'string'},
                  'notes': {'type': 'string'},
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
        'description': 'Manage factory layouts, zones, and machine positions (create_layout, create_zone, update_zone, delete_zone, set_machine_position, delete_machine_position).',
        'parameters': {
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
        'description': 'Manage technician skill matrix and daily availability (add_skill, update_skill, delete_skill, set_availability).',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'description': 'add_skill, update_skill, delete_skill, set_availability'},
            'technician_identifier': {'type': 'string'},
            'skill_name': {'type': 'string'},
            'proficiency_level': {'type': 'string'},
            'certified': {'type': 'boolean'},
            'available_date': {'type': 'string'},
            'available_hours': {'type': 'number'},
            'reserved_hours': {'type': 'number'},
          },
          'required': ['action', 'technician_identifier'],
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
  ];

  static final _anthropicTools = [
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
      'description': 'Manage technician skill matrix and daily availability (add_skill, update_skill, delete_skill, set_availability).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'add_skill, update_skill, delete_skill, set_availability'},
          'technician_identifier': {'type': 'string'},
          'skill_name': {'type': 'string'},
          'proficiency_level': {'type': 'string'},
          'certified': {'type': 'boolean'},
          'available_date': {'type': 'string'},
          'available_hours': {'type': 'number'},
          'reserved_hours': {'type': 'number'},
        },
        'required': ['action', 'technician_identifier'],
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
          return await _testOpenAiCompatible(config);
      }
    } catch (_) {
      return false;
    }
  }

  static Future<String> chat({
    required AiProviderConfig config,
    required List<AiConversationMessage> history,
    required String userMessage,
  }) async {
    await _ensureProviderReachable(config);

    switch (config.provider) {
      case AiProviderKind.gemini:
        return _chatWithGemini(config, history, userMessage);
      case AiProviderKind.claude:
        return _chatWithClaude(config, history, userMessage);
      case AiProviderKind.ollama:
        return _chatWithOllama(config, history, userMessage);
      case AiProviderKind.openai:
      case AiProviderKind.deepseek:
      case AiProviderKind.grok:
      case AiProviderKind.mistral:
        return _chatWithOpenAiCompatible(config, history, userMessage);
    }
  }

  static Future<String> _chatWithGemini(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage,
  ) async {
    final model = GenerativeModel(
      model: config.model,
      apiKey: config.apiKey,
      systemInstruction: Content.system(_systemInstruction),
      tools: [
        Tool(
          functionDeclarations: [
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
            _registerMachinesTool,
            _createPmPlansTool,
            _registerSparePartsTool,
            _createWorkOrderTool,
            _searchVectorKnowledgeTool,
            _queryDbTool,
            _getTablesTool,
            _getSchemaTool,
            _findMachineAssetsTool,
            _externalWebSearchTool,
            _externalImageSearchTool,
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
    var response = await session.sendMessage(Content.text(userMessage));

    for (var i = 0; i < 8 && response.functionCalls.isNotEmpty; i++) {
      final functionResponses = <FunctionResponse>[];

      for (final call in response.functionCalls) {
        final result = await AiToolHandler.handleToolCall(
          call.name,
          call.args.cast<String, dynamic>(),
        );
        functionResponses.add(FunctionResponse(call.name, {'output': result}));
      }

      response = await session.sendMessage(
        Content.functionResponses(functionResponses),
      );
    }

    return response.text ?? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
  }

  static Future<String> _chatWithOpenAiCompatible(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemInstruction},
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userMessage},
    ];

    for (var i = 0; i < 8; i++) {
      final json = await _postJson(
        _normalizeBaseUrl(config.resolvedBaseUrl, '/chat/completions'),
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
        body: {
          'model': config.model,
          'messages': messages,
          'tools': _openAiTools,
          'tool_choice': 'auto',
          'temperature': 0.3,
          'max_tokens': 8192,
        },
      );

      final choices = (json['choices'] as List?) ?? const [];
      if (choices.isEmpty) {
        throw Exception('No choices returned from AI provider');
      }

      final choice = choices.first as Map<String, dynamic>;
      final message =
          (choice['message'] as Map?)?.cast<String, dynamic>() ?? {};
      final toolCalls = (message['tool_calls'] as List?) ?? const [];

      if (toolCalls.isEmpty) {
        final text = _extractOpenAiContent(message['content']);
        return text.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : text;
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
        final result = await AiToolHandler.handleToolCall(
          function['name']?.toString() ?? '',
          args,
        );
        messages.add({
          'role': 'tool',
          'tool_call_id': rawCall['id'],
          'content': result,
        });
      }
    }

    return 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
  }

  static Future<String> _chatWithClaude(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage,
  ) async {
    final messages = <Map<String, dynamic>>[
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userMessage},
    ];

    for (var i = 0; i < 8; i++) {
      final json = await _postJson(
        _normalizeBaseUrl(config.resolvedBaseUrl, '/messages'),
        headers: {
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: {
          'model': config.model,
          'system': _systemInstruction,
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
        if (type == 'text') {
          final text = block['text']?.toString() ?? '';
          if (text.isNotEmpty) textParts.add(text);
          continue;
        }
        if (type == 'tool_use') {
          final result = await AiToolHandler.handleToolCall(
            block['name']?.toString() ?? '',
            (block['input'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{},
          );
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': block['id'],
            'content': result,
          });
        }
      }

      if (toolResults.isEmpty) {
        final text = textParts.join('\n').trim();
        return text.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : text;
      }

      messages.add({'role': 'assistant', 'content': content});
      messages.add({'role': 'user', 'content': toolResults});
    }

    return 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
  }

  static Future<String> _chatWithOllama(
    AiProviderConfig config,
    List<AiConversationMessage> history,
    String userMessage,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemInstruction},
      ...history.map(
        (message) => {
          'role': message.role == 'assistant' ? 'assistant' : 'user',
          'content': message.content,
        },
      ),
      {'role': 'user', 'content': userMessage},
    ];

    for (var i = 0; i < 8; i++) {
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

      if (toolCalls.isEmpty) {
        final text = message['content']?.toString().trim() ?? '';
        return text.isEmpty ? 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ' : text;
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
        final result = await AiToolHandler.handleToolCall(
          function['name']?.toString() ?? '',
          args,
        );
        messages.add({
          'role': 'tool',
          'tool_call_id': rawCall['id'],
          'content': result,
        });
      }
    }

    return 'ไม่สามารถประมวลผลคำตอบได้ในขณะนี้ครับ';
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
    await _postJson(
      _normalizeBaseUrl(config.resolvedBaseUrl, '/chat/completions'),
      headers: {'Authorization': 'Bearer ${config.apiKey}'},
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
