-- =============================================================================
-- MASAPP Database Schema — Maintenance Super App
-- SQLite Version (Shared Offline File)
-- Generated: 2026-04-17
-- =============================================================================

-- =============================================================================
PRAGMA foreign_keys = OFF;

-- Drop ALL tables in reverse order of dependencies to ensure clean slate
DROP TABLE IF EXISTS handover_attachments;
DROP TABLE IF EXISTS handover_checklist_results;
DROP TABLE IF EXISTS handover_checklist_templates;
DROP TABLE IF EXISTS machine_handover;
DROP TABLE IF EXISTS machine_specs;
DROP TABLE IF EXISTS permit_safety_checks;
DROP TABLE IF EXISTS work_permits;
DROP TABLE IF EXISTS spare_parts_transactions;
DROP TABLE IF EXISTS spare_parts_inventory;
DROP TABLE IF EXISTS spare_parts;
DROP TABLE IF EXISTS technician_availability;
DROP TABLE IF EXISTS technician_skills;
DROP TABLE IF EXISTS pm_am_executions;
DROP TABLE IF EXISTS pm_am_tasks;
DROP TABLE IF EXISTS pm_am_schedules;
DROP TABLE IF EXISTS pm_am_plans;
DROP TABLE IF EXISTS machine_positions;
DROP TABLE IF EXISTS layout_zones;
DROP TABLE IF EXISTS factory_layouts;
DROP TABLE IF EXISTS work_order_rca;
DROP TABLE IF EXISTS work_order_labor;
DROP TABLE IF EXISTS work_orders;
DROP TABLE IF EXISTS machine_running_hours;
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS user_sessions;
DROP TABLE IF EXISTS app_settings;
DROP TABLE IF EXISTS machines;
DROP TABLE IF EXISTS machine_categories;
DROP TABLE IF EXISTS suppliers;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS departments;

PRAGMA foreign_keys = ON;

-- MODULE 10: USER MANAGEMENT
-- =============================================================================

CREATE TABLE departments (
  dept_id      TEXT PRIMARY KEY,
  dept_code    TEXT UNIQUE NOT NULL,
  dept_name    TEXT NOT NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE users (
  user_id       TEXT PRIMARY KEY,
  employee_no   TEXT UNIQUE,
  username      TEXT UNIQUE NOT NULL,
  full_name     TEXT NOT NULL,
  email         TEXT,
  phone         TEXT,
  role          TEXT NOT NULL DEFAULT 'operator', -- operator, viewer, technician, safety, engineer, executive, admin
  dept_id       TEXT REFERENCES departments(dept_id),
  password_hash TEXT NOT NULL,           -- bcrypt hash
  approval_pin_hash TEXT,                -- numeric PIN hash for sign-offs
  theme_preference TEXT NOT NULL DEFAULT 'dark', -- light, dark
  is_active     INTEGER NOT NULL DEFAULT 1,
  last_login_at DATETIME,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_sessions (
  session_id    TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(user_id),
  ip_address    TEXT,
  hostname      TEXT,
  login_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  logout_at     DATETIME,
  is_active     INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE audit_log (
  log_id        INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name    TEXT NOT NULL,
  record_id     TEXT,
  action        TEXT NOT NULL, -- INSERT / UPDATE / DELETE
  user_id       TEXT REFERENCES users(user_id),
  username      TEXT,
  ip_address    TEXT,
  hostname      TEXT,
  old_data      TEXT, -- JSON string
  new_data      TEXT, -- JSON string
  changed_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indices
CREATE INDEX idx_audit_log_table ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_user ON audit_log(user_id);

-- =============================================================================
-- MODULE 1: MACHINE INTAKE & DIGITAL HANDOVER
-- =============================================================================

CREATE TABLE suppliers (
  supplier_id   TEXT PRIMARY KEY,
  supplier_code TEXT UNIQUE NOT NULL,
  name          TEXT NOT NULL,
  contact_name  TEXT,
  phone         TEXT,
  email         TEXT,
  address       TEXT,
  is_approved   INTEGER NOT NULL DEFAULT 0,
  is_active     INTEGER NOT NULL DEFAULT 1,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE machine_categories (
  category_id   TEXT PRIMARY KEY,
  code          TEXT UNIQUE NOT NULL,
  name          TEXT NOT NULL,
  description   TEXT,
  parent_id     TEXT REFERENCES machine_categories(category_id)
);

CREATE TABLE machines (
  machine_id      TEXT PRIMARY KEY,
  machine_no      TEXT UNIQUE NOT NULL,
  machine_name    TEXT,
  asset_no        TEXT UNIQUE,
  brand           TEXT,
  model           TEXT,
  serial_no       TEXT,
  category_id     TEXT REFERENCES machine_categories(category_id),
  dept_id         TEXT REFERENCES departments(dept_id),
  location        TEXT,
  floor_id        TEXT,
  status          TEXT NOT NULL DEFAULT 'normal', -- normal, breakdown, pm, am, offline, decommissioned
  installation_date DATE,
  warranty_expiry   DATE,
  purchase_cost   REAL,
  supplier_id     TEXT REFERENCES suppliers(supplier_id),
  handover_completed INTEGER NOT NULL DEFAULT 0,
  is_active       INTEGER NOT NULL DEFAULT 1,
  notes           TEXT,
  created_by      TEXT REFERENCES users(user_id),
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE machine_specs (
  spec_id       TEXT PRIMARY KEY,
  machine_id    TEXT NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
  power_kw      REAL,
  voltage_v     REAL,
  current_a     REAL,
  frequency_hz  REAL,
  capacity      REAL,
  capacity_unit TEXT,
  weight_kg     REAL,
  dim_length_mm REAL,
  dim_width_mm  REAL,
  dim_height_mm REAL,
  rpm           REAL,
  extra_specs   TEXT, -- JSON
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (machine_id)
);

CREATE TABLE machine_handover (
  handover_id   TEXT PRIMARY KEY,
  machine_id    TEXT NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
  stage         TEXT NOT NULL, -- stage1, stage2, stage3
  status        TEXT NOT NULL DEFAULT 'pending', -- pending, in_progress, passed, failed, approved
  performed_by  TEXT REFERENCES users(user_id),
  approved_by   TEXT REFERENCES users(user_id),
  performed_at  DATETIME,
  approved_at   DATETIME,
  notes         TEXT,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (machine_id, stage)
);

CREATE TABLE handover_checklist_templates (
  template_id   TEXT PRIMARY KEY,
  stage         TEXT NOT NULL,
  item_order    INTEGER NOT NULL,
  item_code     TEXT,
  item_name     TEXT NOT NULL,
  item_type     TEXT DEFAULT 'pass_fail',
  is_required   INTEGER NOT NULL DEFAULT 1,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE handover_checklist_results (
  result_id     TEXT PRIMARY KEY,
  handover_id   TEXT NOT NULL REFERENCES machine_handover(handover_id) ON DELETE CASCADE,
  template_id   TEXT REFERENCES handover_checklist_templates(template_id),
  item_name     TEXT NOT NULL,
  result        TEXT, -- pass, fail, na
  actual_value  TEXT,
  remarks       TEXT,
  checked_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE machine_snapshots (
  snapshot_id   TEXT PRIMARY KEY,
  machine_id    TEXT NOT NULL,
  machine_no    TEXT NOT NULL,
  machine_name  TEXT,
  brand         TEXT,
  model         TEXT,
  dept_name     TEXT,
  location      TEXT,
  captured_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- SYSTEM SETTINGS
-- =============================================================================

CREATE TABLE app_settings (
  setting_key   TEXT PRIMARY KEY,
  setting_value TEXT NOT NULL,
  description   TEXT,
  updated_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- MODULE 5: WORK ORDERS & REPAIRS
-- =============================================================================

CREATE TABLE work_orders (
  wo_id             TEXT PRIMARY KEY,
  wo_no             TEXT UNIQUE NOT NULL, -- Auto-generated: WO-YYYY-00001
  machine_id        TEXT NOT NULL, -- Logical reference
  snapshot_id       TEXT REFERENCES machine_snapshots(snapshot_id),
  status            TEXT NOT NULL DEFAULT 'pending', -- pending, approved, inProgress, completed, cancelled, rejected
  priority          TEXT NOT NULL DEFAULT 'normal', -- low, normal, high, urgent
  title             TEXT NOT NULL,
  description       TEXT,
  failure_symptom   TEXT,
  failure_cause     TEXT,
  assigned_to       TEXT REFERENCES users(user_id),
  approved_by       TEXT REFERENCES users(user_id),
  estimated_hours   REAL,
  actual_hours      REAL,
  started_at        DATETIME,
  completed_at      DATETIME,
  approved_at       DATETIME,
  created_by        TEXT NOT NULL REFERENCES users(user_id),
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_work_orders_machine ON work_orders(machine_id);
CREATE INDEX idx_work_orders_status ON work_orders(status);
CREATE INDEX idx_work_orders_assigned_to ON work_orders(assigned_to);

CREATE TABLE work_order_labor (
  labor_id          TEXT PRIMARY KEY,
  wo_id             TEXT NOT NULL REFERENCES work_orders(wo_id) ON DELETE CASCADE,
  technician_id     TEXT NOT NULL REFERENCES users(user_id),
  start_time        DATETIME NOT NULL,
  end_time          DATETIME NOT NULL,
  hours             REAL NOT NULL,
  task_description  TEXT,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_work_order_labor_wo ON work_order_labor(wo_id);
CREATE INDEX idx_work_order_labor_technician ON work_order_labor(technician_id);

CREATE TABLE work_order_rca (
  rca_id            TEXT PRIMARY KEY,
  wo_id             TEXT NOT NULL UNIQUE REFERENCES work_orders(wo_id) ON DELETE CASCADE,
  failure_type      TEXT, -- breakdown, wear, design, process, environment
  why_1             TEXT,
  why_2             TEXT,
  why_3             TEXT,
  why_4             TEXT,
  why_5             TEXT,
  root_cause        TEXT NOT NULL,
  correction_action TEXT,
  preventive_action TEXT,
  analyzed_by       TEXT REFERENCES users(user_id),
  analyzed_at       DATETIME,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- MODULE 6: FACTORY LAYOUT VISUALIZATION
-- =============================================================================

CREATE TABLE factory_layouts (
  layout_id         TEXT PRIMARY KEY,
  layout_name       TEXT NOT NULL,
  description       TEXT,
  floor_no          INTEGER,
  width_m           REAL,
  height_m          REAL,
  scale_pixel_per_m REAL DEFAULT 50.0,
  is_active         INTEGER NOT NULL DEFAULT 1,
  created_by        TEXT REFERENCES users(user_id),
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE layout_zones (
  zone_id           TEXT PRIMARY KEY,
  layout_id         TEXT NOT NULL REFERENCES factory_layouts(layout_id) ON DELETE CASCADE,
  zone_name         TEXT NOT NULL,
  zone_type         TEXT, -- assembly, storage, maintenance, safety, etc
  x_start           REAL NOT NULL,
  y_start           REAL NOT NULL,
  x_end             REAL NOT NULL,
  y_end             REAL NOT NULL,
  background_color  TEXT DEFAULT '#E8F5E9',
  border_color      TEXT DEFAULT '#4CAF50',
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_layout_zones_layout ON layout_zones(layout_id);

CREATE TABLE machine_positions (
  position_id       TEXT PRIMARY KEY,
  layout_id         TEXT NOT NULL REFERENCES factory_layouts(layout_id) ON DELETE CASCADE,
  machine_id        TEXT NOT NULL REFERENCES machines(machine_id),
  zone_id           TEXT REFERENCES layout_zones(zone_id),
  x_position        REAL NOT NULL,
  y_position        REAL NOT NULL,
  width             REAL DEFAULT 40.0,
  height            REAL DEFAULT 40.0,
  status_color      TEXT DEFAULT '#4CAF50', -- green, yellow, red, gray, orange
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (layout_id, machine_id)
);

CREATE INDEX idx_machine_positions_layout ON machine_positions(layout_id);
CREATE INDEX idx_machine_positions_machine ON machine_positions(machine_id);

-- =============================================================================
-- MODULE 7: ANALYTICS & INSIGHTS
-- =============================================================================

CREATE TABLE machine_running_hours (
  hours_id          TEXT PRIMARY KEY,
  machine_id        TEXT NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
  cumulative_hours  REAL NOT NULL DEFAULT 0,
  daily_hours       REAL DEFAULT 0,
  recorded_date     DATE NOT NULL,
  recorded_by       TEXT REFERENCES users(user_id),
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_machine_running_hours_machine ON machine_running_hours(machine_id);
CREATE INDEX idx_machine_running_hours_date ON machine_running_hours(recorded_date);

-- =============================================================================
-- MODULE 8: PREVENTIVE & AUTONOMOUS MAINTENANCE (PM/AM)
-- =============================================================================

CREATE TABLE pm_am_plans (
  plan_id           TEXT PRIMARY KEY,
  machine_id        TEXT NOT NULL,
  snapshot_id       TEXT REFERENCES machine_snapshots(snapshot_id),
  plan_type         TEXT NOT NULL, -- PM (preventive), AM (autonomous)
  plan_code         TEXT UNIQUE NOT NULL,
  plan_name         TEXT NOT NULL,
  description       TEXT,
  frequency_days    INTEGER,
  frequency_hours   REAL,
  estimated_hours   REAL,
  status            TEXT NOT NULL DEFAULT 'active', -- active, suspended, completed
  created_by        TEXT REFERENCES users(user_id),
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE pm_am_schedules (
  schedule_id       TEXT PRIMARY KEY,
  plan_id           TEXT NOT NULL REFERENCES pm_am_plans(plan_id) ON DELETE CASCADE,
  scheduled_date    DATE NOT NULL,
  scheduled_by      TEXT REFERENCES users(user_id),
  assigned_to       TEXT REFERENCES users(user_id),
  status            TEXT NOT NULL DEFAULT 'pending', -- pending, overdue, in_progress, completed, cancelled
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_pm_am_schedules_machine ON pm_am_schedules(schedule_id);
CREATE INDEX idx_pm_am_schedules_date ON pm_am_schedules(scheduled_date);

CREATE TABLE pm_am_tasks (
  task_id           TEXT PRIMARY KEY,
  plan_id           TEXT NOT NULL REFERENCES pm_am_plans(plan_id) ON DELETE CASCADE,
  task_order        INTEGER NOT NULL,
  task_name         TEXT NOT NULL,
  task_code         TEXT,
  task_type         TEXT, -- clean, lubricate, tighten, inspect, replace, calibrate
  expected_result   TEXT,
  is_critical       INTEGER DEFAULT 0,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE pm_am_executions (
  execution_id      TEXT PRIMARY KEY,
  schedule_id       TEXT NOT NULL REFERENCES pm_am_schedules(schedule_id) ON DELETE CASCADE,
  task_id           TEXT NOT NULL REFERENCES pm_am_tasks(task_id),
  executed_by       TEXT REFERENCES users(user_id),
  started_at        DATETIME,
  completed_at      DATETIME,
  result            TEXT, -- pass, fail, na
  remarks           TEXT,
  parts_used        TEXT, -- JSON array of part IDs
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- MODULE 9: E-WORK PERMIT SYSTEM
-- =============================================================================

CREATE TABLE work_permits (
  permit_id         TEXT PRIMARY KEY,
  permit_no         TEXT UNIQUE NOT NULL,
  permit_type       TEXT NOT NULL, -- hot_work, confined_space, electrical, heights, energy_isolation
  machine_id        TEXT,
  snapshot_id       TEXT REFERENCES machine_snapshots(snapshot_id),
  department        TEXT,
  description       TEXT NOT NULL,
  duration_hours    INTEGER,
  requestor         TEXT NOT NULL REFERENCES users(user_id),
  requester_name    TEXT NOT NULL,
  authorized_by     TEXT REFERENCES users(user_id),
  authorized_at     DATETIME,
  authorization_pin TEXT, -- 4-digit PIN for digital sign-off
  status            TEXT NOT NULL DEFAULT 'pending', -- pending, approved, in_progress, completed, cancelled, rejected
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at      DATETIME,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_work_permits_machine ON work_permits(machine_id);
CREATE INDEX idx_work_permits_status ON work_permits(status);

CREATE TABLE permit_safety_checks (
  check_id          TEXT PRIMARY KEY,
  permit_id         TEXT NOT NULL REFERENCES work_permits(permit_id) ON DELETE CASCADE,
  check_item        TEXT NOT NULL,
  check_type        TEXT, -- ppe, guards, ventilation, isolation, etc
  is_passed         INTEGER NOT NULL DEFAULT 0,
  checked_by        TEXT REFERENCES users(user_id),
  checked_at        DATETIME,
  remarks           TEXT
);

-- =============================================================================
-- MODULE 10: SPARE PARTS & WAREHOUSE
-- =============================================================================

CREATE TABLE spare_parts (
  part_id           TEXT PRIMARY KEY,
  part_code         TEXT UNIQUE NOT NULL,
  part_name         TEXT NOT NULL,
  supplier_id       TEXT REFERENCES suppliers(supplier_id),
  category          TEXT,
  unit_cost         REAL,
  reorder_level     INTEGER DEFAULT 5,
  lead_time_days    INTEGER,
  is_active         INTEGER NOT NULL DEFAULT 1,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE spare_parts_inventory (
  inventory_id      TEXT PRIMARY KEY,
  part_id           TEXT NOT NULL REFERENCES spare_parts(part_id),
  quantity_on_hand  INTEGER NOT NULL DEFAULT 0,
  quantity_reserved INTEGER NOT NULL DEFAULT 0,
  location          TEXT,
  last_counted_at   DATETIME,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (part_id)
);

CREATE TABLE spare_parts_transactions (
  trans_id          TEXT PRIMARY KEY,
  part_id           TEXT NOT NULL REFERENCES spare_parts(part_id),
  trans_type        TEXT NOT NULL, -- in, out, adjustment, return
  quantity          INTEGER NOT NULL,
  reference_id      TEXT, -- WO ID, PM schedule ID, etc
  trans_by          TEXT REFERENCES users(user_id),
  remarks           TEXT,
  trans_date        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- MODULE 11: WORKFORCE & SMART DISPATCH
-- =============================================================================

CREATE TABLE technician_skills (
  skill_id          TEXT PRIMARY KEY,
  technician_id     TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  skill_name        TEXT NOT NULL,
  proficiency_level TEXT DEFAULT 'intermediate', -- basic, intermediate, expert
  certified         INTEGER DEFAULT 0,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE technician_availability (
  avail_id          TEXT PRIMARY KEY,
  technician_id     TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  available_date    DATE NOT NULL,
  available_hours   REAL DEFAULT 8.0,
  reserved_hours    REAL DEFAULT 0,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (technician_id, available_date)
);

CREATE INDEX idx_tech_availability_date ON technician_availability(available_date);
