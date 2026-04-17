-- =============================================================================
-- MASAPP Database Schema — Maintenance Super App
-- PostgreSQL 15+
-- Generated: 2026-04-17
-- =============================================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";     -- Full-text search (Thai + EN)
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- =============================================================================
-- ENUM TYPES
-- =============================================================================
CREATE TYPE user_role AS ENUM (
  'operator', 'viewer', 'technician', 'safety', 'engineer', 'executive', 'admin'
);

CREATE TYPE machine_status AS ENUM (
  'normal', 'breakdown', 'pm', 'am', 'offline', 'decommissioned'
);

CREATE TYPE handover_stage AS ENUM ('stage1', 'stage2', 'stage3');
CREATE TYPE handover_status AS ENUM ('pending', 'in_progress', 'passed', 'failed', 'approved');

CREATE TYPE wo_type AS ENUM ('repair', 'modification', 'am_defect', 'pm');
CREATE TYPE wo_priority AS ENUM ('critical', 'high', 'medium', 'low');
CREATE TYPE wo_status AS ENUM ('open', 'assigned', 'in_progress', 'pending_parts', 'completed', 'closed', 'cancelled');

CREATE TYPE permit_type AS ENUM ('hot_work', 'high_level', 'confined_space', 'electrical', 'general');
CREATE TYPE permit_status AS ENUM ('draft', 'pending_approval', 'active', 'expired', 'revoked', 'closed');

CREATE TYPE stock_tx_type AS ENUM ('receive', 'issue', 'return_to_stock', 'adjustment', 'reservation', 'reservation_cancel');

CREATE TYPE doc_type AS ENUM ('drawing', 'manual', 'sop', 'certificate', 'training_record', 'other');

CREATE TYPE pm_frequency_type AS ENUM ('calendar_daily', 'calendar_weekly', 'calendar_monthly', 'calendar_yearly', 'running_hours', 'production_count');

-- =============================================================================
-- MODULE 10: USER MANAGEMENT
-- =============================================================================

CREATE TABLE departments (
  dept_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  dept_code    VARCHAR(20) UNIQUE NOT NULL,
  dept_name    VARCHAR(100) NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE users (
  user_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_no   VARCHAR(50) UNIQUE,
  username      VARCHAR(100) UNIQUE NOT NULL,
  full_name     VARCHAR(200) NOT NULL,
  email         VARCHAR(200),
  phone         VARCHAR(50),
  role          user_role NOT NULL DEFAULT 'operator',
  dept_id       UUID REFERENCES departments(dept_id),
  password_hash VARCHAR(256) NOT NULL,           -- SHA-256 hex
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE user_sessions (
  session_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(user_id),
  ip_address    INET,
  hostname      VARCHAR(255),
  login_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  logout_at     TIMESTAMPTZ,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE audit_log (
  log_id        BIGSERIAL PRIMARY KEY,
  table_name    VARCHAR(100) NOT NULL,
  record_id     TEXT,          -- UUID or PK of affected record
  action        VARCHAR(20) NOT NULL,  -- INSERT / UPDATE / DELETE
  user_id       UUID REFERENCES users(user_id),
  username      VARCHAR(100),
  ip_address    INET,
  hostname      VARCHAR(255),
  old_data      JSONB,
  new_data      JSONB,
  changed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_log_table ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_user ON audit_log(user_id);
CREATE INDEX idx_audit_log_time ON audit_log(changed_at DESC);

-- =============================================================================
-- MODULE 1: MACHINE INTAKE & DIGITAL HANDOVER
-- =============================================================================

CREATE TABLE suppliers (
  supplier_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  supplier_code VARCHAR(50) UNIQUE NOT NULL,
  name          VARCHAR(200) NOT NULL,
  contact_name  VARCHAR(200),
  phone         VARCHAR(100),
  email         VARCHAR(200),
  address       TEXT,
  is_approved   BOOLEAN NOT NULL DEFAULT FALSE, -- ASL flag
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE machine_categories (
  category_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code          VARCHAR(50) UNIQUE NOT NULL,
  name          VARCHAR(200) NOT NULL,
  description   TEXT,
  parent_id     UUID REFERENCES machine_categories(category_id)
);

CREATE TABLE machines (
  machine_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_no      VARCHAR(50) UNIQUE NOT NULL,   -- e.g. DP1, MDB-01
  asset_no        VARCHAR(100) UNIQUE,
  brand           VARCHAR(200),
  model           VARCHAR(200),
  serial_no       VARCHAR(200),
  category_id     UUID REFERENCES machine_categories(category_id),
  dept_id         UUID REFERENCES departments(dept_id),
  location        VARCHAR(200),                   -- free-text location
  floor_id        UUID,                           -- FK added later (factory_floors)
  status          machine_status NOT NULL DEFAULT 'normal',
  installation_date DATE,
  warranty_expiry   DATE,
  purchase_cost   NUMERIC(15,2),
  supplier_id     UUID REFERENCES suppliers(supplier_id),
  handover_completed BOOLEAN NOT NULL DEFAULT FALSE,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  notes           TEXT,
  created_by      UUID REFERENCES users(user_id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_machines_status ON machines(status);
CREATE INDEX idx_machines_category ON machines(category_id);

CREATE TABLE machine_specs (
  spec_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
  power_kw      NUMERIC(10,3),
  voltage_v     NUMERIC(10,2),
  current_a     NUMERIC(10,2),
  frequency_hz  NUMERIC(6,2),
  capacity      NUMERIC(15,3),
  capacity_unit VARCHAR(50),
  weight_kg     NUMERIC(10,2),
  dim_length_mm NUMERIC(10,2),
  dim_width_mm  NUMERIC(10,2),
  dim_height_mm NUMERIC(10,2),
  rpm           NUMERIC(10,2),
  extra_specs   JSONB,           -- flexible additional technical specs
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (machine_id)
);

-- Handover records per stage
CREATE TABLE machine_handover (
  handover_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
  stage         handover_stage NOT NULL,
  status        handover_status NOT NULL DEFAULT 'pending',
  performed_by  UUID REFERENCES users(user_id),
  approved_by   UUID REFERENCES users(user_id),
  performed_at  TIMESTAMPTZ,
  approved_at   TIMESTAMPTZ,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (machine_id, stage)
);

CREATE TABLE handover_checklist_templates (
  template_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  stage         handover_stage NOT NULL,
  item_order    INT NOT NULL,
  item_code     VARCHAR(50),
  item_name     VARCHAR(500) NOT NULL,
  item_type     VARCHAR(50) DEFAULT 'pass_fail',  -- pass_fail | text | number
  is_required   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE handover_checklist_results (
  result_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  handover_id   UUID NOT NULL REFERENCES machine_handover(handover_id) ON DELETE CASCADE,
  template_id   UUID REFERENCES handover_checklist_templates(template_id),
  item_name     VARCHAR(500) NOT NULL,
  result        VARCHAR(20),   -- 'pass' | 'fail' | 'na'
  actual_value  VARCHAR(500),  -- for numeric/text items
  remarks       TEXT,
  checked_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE handover_attachments (
  attachment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  handover_id   UUID NOT NULL REFERENCES machine_handover(handover_id) ON DELETE CASCADE,
  file_name     VARCHAR(500) NOT NULL,
  file_path     TEXT NOT NULL,
  file_size     BIGINT,
  mime_type     VARCHAR(200),
  uploaded_by   UUID REFERENCES users(user_id),
  uploaded_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Running hours tracking (core metric)
CREATE TABLE machine_running_hours (
  record_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id),
  recorded_date DATE NOT NULL,
  hours_today   NUMERIC(6,2) NOT NULL DEFAULT 0,
  cumulative_hours NUMERIC(12,2) NOT NULL DEFAULT 0,
  recorded_by   UUID REFERENCES users(user_id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (machine_id, recorded_date)
);

-- =============================================================================
-- MODULE 2: FACTORY LAYOUT
-- =============================================================================

CREATE TABLE factory_floors (
  floor_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  building_name VARCHAR(200) NOT NULL,
  floor_name    VARCHAR(200) NOT NULL,
  floor_order   INT NOT NULL DEFAULT 0,
  image_path    TEXT,
  image_width   INT,
  image_height  INT,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE machine_positions (
  position_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
  floor_id      UUID NOT NULL REFERENCES factory_floors(floor_id),
  pos_x_pct    NUMERIC(6,4) NOT NULL,   -- % of image width (0.0–1.0)
  pos_y_pct    NUMERIC(6,4) NOT NULL,
  label_offset_x NUMERIC(6,2) DEFAULT 0,
  label_offset_y NUMERIC(6,2) DEFAULT 0,
  updated_by    UUID REFERENCES users(user_id),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (machine_id)
);

-- =============================================================================
-- MODULE 3: MACHINE REGISTRY & DOCUMENT CONTROL
-- =============================================================================

CREATE TABLE documents (
  doc_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID REFERENCES machines(machine_id),
  doc_type      doc_type NOT NULL,
  doc_title     VARCHAR(500) NOT NULL,
  doc_no        VARCHAR(100),
  revision_no   VARCHAR(20) NOT NULL DEFAULT 'Rev.00',
  file_path     TEXT NOT NULL,
  file_name     VARCHAR(500),
  file_size     BIGINT,
  mime_type     VARCHAR(200),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,   -- only latest active
  superseded_by UUID REFERENCES documents(doc_id),
  uploaded_by   UUID REFERENCES users(user_id),
  approved_by   UUID REFERENCES users(user_id),
  effective_date DATE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_documents_machine ON documents(machine_id);
CREATE INDEX idx_documents_active ON documents(machine_id, is_active) WHERE is_active = TRUE;

CREATE TABLE measuring_tools (
  tool_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tool_code       VARCHAR(100) UNIQUE NOT NULL,
  name            VARCHAR(300) NOT NULL,
  brand           VARCHAR(200),
  model           VARCHAR(200),
  serial_no       VARCHAR(200),
  location        VARCHAR(300),
  calibration_interval_months INT NOT NULL DEFAULT 12,
  last_calibrated DATE,
  calibration_due DATE,
  responsible_user UUID REFERENCES users(user_id),
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE calibration_history (
  cal_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tool_id       UUID NOT NULL REFERENCES measuring_tools(tool_id),
  calibrated_at DATE NOT NULL,
  result        VARCHAR(50),   -- 'pass' | 'fail' | 'adjusted'
  calibrated_by VARCHAR(200),  -- external lab name
  certificate_path TEXT,
  next_due_date DATE,
  notes         TEXT,
  recorded_by   UUID REFERENCES users(user_id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MODULE 4: PM / AM
-- =============================================================================

CREATE TABLE pm_plans (
  plan_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id),
  plan_name     VARCHAR(300) NOT NULL,
  frequency_type pm_frequency_type NOT NULL,
  interval_value INT NOT NULL,             -- e.g. 500 (hours) or 1 (month)
  last_done_at  DATE,
  next_due      DATE,
  estimated_duration_hrs NUMERIC(6,2),
  assigned_team VARCHAR(200),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_by    UUID REFERENCES users(user_id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE pm_checklist_templates (
  template_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan_id       UUID NOT NULL REFERENCES pm_plans(plan_id) ON DELETE CASCADE,
  item_order    INT NOT NULL,
  item_name     VARCHAR(500) NOT NULL,
  item_type     VARCHAR(50) DEFAULT 'pass_fail',
  tolerance_min NUMERIC(15,4),
  tolerance_max NUMERIC(15,4),
  unit          VARCHAR(50),
  is_required   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE pm_work_orders (
  pm_wo_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan_id       UUID NOT NULL REFERENCES pm_plans(plan_id),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id),
  scheduled_date DATE NOT NULL,
  actual_start  TIMESTAMPTZ,
  actual_end    TIMESTAMPTZ,
  status        wo_status NOT NULL DEFAULT 'open',
  assigned_to   UUID REFERENCES users(user_id),
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE pm_checklist_results (
  result_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pm_wo_id      UUID NOT NULL REFERENCES pm_work_orders(pm_wo_id) ON DELETE CASCADE,
  template_id   UUID REFERENCES pm_checklist_templates(template_id),
  item_name     VARCHAR(500) NOT NULL,
  result        VARCHAR(20),
  actual_value  VARCHAR(500),
  remarks       TEXT,
  checked_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE am_schedules (
  schedule_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id     UUID NOT NULL REFERENCES machines(machine_id),
  checklist_name VARCHAR(300) NOT NULL,
  shift          VARCHAR(50),       -- 'all' | 'day' | 'night'
  frequency      VARCHAR(50) DEFAULT 'daily',
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE am_checklist_items (
  item_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  schedule_id   UUID NOT NULL REFERENCES am_schedules(schedule_id) ON DELETE CASCADE,
  item_order    INT NOT NULL,
  item_name     VARCHAR(500) NOT NULL,
  item_type     VARCHAR(50) DEFAULT 'pass_fail',
  is_required   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE am_daily_records (
  record_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  schedule_id   UUID NOT NULL REFERENCES am_schedules(schedule_id),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id),
  recorded_date DATE NOT NULL,
  shift         VARCHAR(50),
  operator_id   UUID REFERENCES users(user_id),
  overall_status VARCHAR(20),    -- 'ok' | 'defect_found'
  submitted_at  TIMESTAMPTZ,
  UNIQUE (schedule_id, recorded_date, shift)
);

CREATE TABLE am_checklist_results (
  result_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  record_id     UUID NOT NULL REFERENCES am_daily_records(record_id) ON DELETE CASCADE,
  item_id       UUID REFERENCES am_checklist_items(item_id),
  item_name     VARCHAR(500) NOT NULL,
  result        VARCHAR(20),
  actual_value  VARCHAR(500),
  remarks       TEXT
);

CREATE TABLE am_defect_tags (
  defect_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  record_id     UUID REFERENCES am_daily_records(record_id),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id),
  description   TEXT NOT NULL,
  photo_path    TEXT,
  severity      wo_priority DEFAULT 'medium',
  work_order_id UUID,             -- FK to work_orders added below
  status        VARCHAR(30) DEFAULT 'open',
  created_by    UUID REFERENCES users(user_id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MODULE 5: WORK ORDERS
-- =============================================================================

CREATE TABLE work_orders (
  wo_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wo_no           VARCHAR(50) UNIQUE NOT NULL,  -- auto-generated: WO-2026-0001
  type            wo_type NOT NULL,
  machine_id      UUID REFERENCES machines(machine_id),
  title           VARCHAR(500) NOT NULL,
  description     TEXT,
  symptom_tags    TEXT[],                        -- categorized symptoms
  priority        wo_priority NOT NULL DEFAULT 'medium',
  status          wo_status NOT NULL DEFAULT 'open',
  sla_hours       NUMERIC(6,1),
  sla_due_at      TIMESTAMPTZ,
  reported_by     UUID REFERENCES users(user_id),
  reported_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  assigned_lead   UUID REFERENCES users(user_id),
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  closed_at       TIMESTAMPTZ,
  closed_by       UUID REFERENCES users(user_id),
  downtime_mins   INT,
  root_cause_done BOOLEAN NOT NULL DEFAULT FALSE,
  satisfaction_rating INT,         -- 1–5 stars
  satisfaction_note   TEXT,
  is_outsourced   BOOLEAN NOT NULL DEFAULT FALSE,
  vendor_id       UUID REFERENCES suppliers(supplier_id),
  vendor_cost     NUMERIC(15,2),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- full-text search vector
  search_vector   TSVECTOR
);

CREATE INDEX idx_wo_status ON work_orders(status);
CREATE INDEX idx_wo_machine ON work_orders(machine_id);
CREATE INDEX idx_wo_priority ON work_orders(priority);
CREATE INDEX idx_wo_search ON work_orders USING GIN(search_vector);
CREATE INDEX idx_wo_reported_at ON work_orders(reported_at DESC);

-- Update search vector trigger function
CREATE OR REPLACE FUNCTION update_wo_search_vector()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector := to_tsvector('english', coalesce(NEW.title, '') || ' ' || coalesce(NEW.description, ''));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER wo_search_update BEFORE INSERT OR UPDATE ON work_orders
FOR EACH ROW EXECUTE FUNCTION update_wo_search_vector();

-- Add FK from am_defect_tags to work_orders
ALTER TABLE am_defect_tags ADD CONSTRAINT fk_defect_wo FOREIGN KEY (work_order_id) REFERENCES work_orders(wo_id);

CREATE TABLE wo_assignments (
  assignment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wo_id         UUID NOT NULL REFERENCES work_orders(wo_id) ON DELETE CASCADE,
  technician_id UUID NOT NULL REFERENCES users(user_id),
  assigned_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at  TIMESTAMPTZ,
  labor_hours   NUMERIC(6,2),
  notes         TEXT
);

CREATE TABLE wo_time_logs (
  log_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wo_id         UUID NOT NULL REFERENCES work_orders(wo_id) ON DELETE CASCADE,
  technician_id UUID NOT NULL REFERENCES users(user_id),
  start_time    TIMESTAMPTZ NOT NULL,
  end_time      TIMESTAMPTZ,
  duration_mins INT,               -- calculated on stop
  activity_desc TEXT
);

CREATE TABLE wo_root_cause (
  rca_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wo_id         UUID NOT NULL REFERENCES work_orders(wo_id) ON DELETE CASCADE,
  why_1         TEXT NOT NULL,
  why_2         TEXT,
  why_3         TEXT,
  why_4         TEXT,
  why_5         TEXT,
  root_cause    TEXT NOT NULL,
  corrective_action TEXT,
  preventive_action TEXT,
  completed_by  UUID REFERENCES users(user_id),
  completed_at  TIMESTAMPTZ,
  UNIQUE (wo_id)
);

CREATE TABLE wo_knowledge_base (
  kb_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID REFERENCES machines(machine_id),
  category_id   UUID REFERENCES machine_categories(category_id),
  symptom       TEXT NOT NULL,
  root_cause    TEXT,
  solution      TEXT NOT NULL,
  time_to_fix_hrs NUMERIC(6,2),
  source_wo_id  UUID REFERENCES work_orders(wo_id),
  usage_count   INT NOT NULL DEFAULT 0,
  is_verified   BOOLEAN NOT NULL DEFAULT FALSE,
  created_by    UUID REFERENCES users(user_id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  search_vector TSVECTOR
);

CREATE INDEX idx_kb_search ON wo_knowledge_base USING GIN(search_vector);

CREATE OR REPLACE FUNCTION update_kb_search_vector()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector := to_tsvector('english', coalesce(NEW.symptom, '') || ' ' || coalesce(NEW.solution, ''));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER kb_search_update BEFORE INSERT OR UPDATE ON wo_knowledge_base
FOR EACH ROW EXECUTE FUNCTION update_kb_search_vector();

CREATE TABLE wo_spare_parts_used (
  usage_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wo_id         UUID NOT NULL REFERENCES work_orders(wo_id),
  part_id       UUID,             -- FK to spare_parts added below
  part_name     VARCHAR(300),
  qty_used      NUMERIC(12,4) NOT NULL,
  unit_cost     NUMERIC(15,2),
  total_cost    NUMERIC(15,2),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE wo_attachments (
  attachment_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  wo_id         UUID NOT NULL REFERENCES work_orders(wo_id) ON DELETE CASCADE,
  file_name     VARCHAR(500) NOT NULL,
  file_path     TEXT NOT NULL,
  file_size     BIGINT,
  mime_type     VARCHAR(200),
  uploaded_by   UUID REFERENCES users(user_id),
  uploaded_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MODULE 6: E-WORK PERMIT
-- =============================================================================

CREATE TABLE work_permits (
  permit_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  permit_no       VARCHAR(50) UNIQUE NOT NULL,
  wo_id           UUID REFERENCES work_orders(wo_id),
  permit_type     permit_type NOT NULL,
  work_description TEXT NOT NULL,
  work_location   VARCHAR(500),
  floor_id        UUID REFERENCES factory_floors(floor_id),
  zone_desc       VARCHAR(500),
  validity_start  TIMESTAMPTZ NOT NULL,
  validity_end    TIMESTAMPTZ NOT NULL,
  status          permit_status NOT NULL DEFAULT 'draft',
  is_simops_cleared BOOLEAN NOT NULL DEFAULT FALSE,
  revoked_by      UUID REFERENCES users(user_id),
  revoke_reason   TEXT,
  revoked_at      TIMESTAMPTZ,
  qr_code_path    TEXT,
  created_by      UUID REFERENCES users(user_id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_permits_status ON work_permits(status);
CREATE INDEX idx_permits_validity ON work_permits(validity_start, validity_end);

CREATE TABLE permit_approvals (
  approval_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  permit_id     UUID NOT NULL REFERENCES work_permits(permit_id),
  approver_id   UUID NOT NULL REFERENCES users(user_id),
  approver_role user_role NOT NULL,
  approval_step VARCHAR(100) NOT NULL,  -- e.g. 'requester', 'safety', 'engineer'
  is_approved   BOOLEAN,
  remarks       TEXT,
  approved_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE permit_workers (
  worker_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  permit_id     UUID NOT NULL REFERENCES work_permits(permit_id),
  user_id       UUID REFERENCES users(user_id),
  full_name     VARCHAR(300) NOT NULL,
  is_contractor BOOLEAN NOT NULL DEFAULT FALSE,
  contractor_id UUID,                  -- FK to contractors
  added_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE permit_gas_tests (
  test_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  permit_id     UUID NOT NULL REFERENCES work_permits(permit_id),
  tested_at     TIMESTAMPTZ NOT NULL,
  tester_name   VARCHAR(300),
  o2_pct        NUMERIC(6,2),
  lel_pct       NUMERIC(6,2),
  co_ppm        NUMERIC(8,2),
  h2s_ppm       NUMERIC(8,2),
  result        VARCHAR(20),   -- 'pass' | 'fail'
  notes         TEXT
);

CREATE TABLE contractors (
  contractor_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          VARCHAR(300) NOT NULL,
  company       VARCHAR(300),
  ic_no         VARCHAR(100),
  phone         VARCHAR(100),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE contractor_certificates (
  cert_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  contractor_id UUID NOT NULL REFERENCES contractors(contractor_id),
  cert_type     VARCHAR(200) NOT NULL,
  cert_no       VARCHAR(200),
  issued_date   DATE,
  expiry_date   DATE NOT NULL,
  file_path     TEXT,
  is_valid      BOOLEAN GENERATED ALWAYS AS (expiry_date >= CURRENT_DATE) STORED,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MODULE 7: SPARE PARTS & WAREHOUSE
-- =============================================================================

CREATE TABLE spare_part_categories (
  cat_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code          VARCHAR(50) UNIQUE NOT NULL,
  name          VARCHAR(200) NOT NULL,
  parent_id     UUID REFERENCES spare_part_categories(cat_id)
);

CREATE TABLE locations (
  location_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  warehouse     VARCHAR(100) NOT NULL,
  zone          VARCHAR(100),
  shelf         VARCHAR(100),
  bin           VARCHAR(100),
  full_address  VARCHAR(500) GENERATED ALWAYS AS (warehouse || '-' || COALESCE(zone,'-') || '-' || COALESCE(shelf,'?') || '-' || COALESCE(bin,'?')) STORED
);

CREATE TABLE spare_parts (
  part_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  part_no         VARCHAR(200) UNIQUE NOT NULL,
  name            VARCHAR(500) NOT NULL,
  name_th         VARCHAR(500),
  description     TEXT,
  category_id     UUID REFERENCES spare_part_categories(cat_id),
  unit            VARCHAR(50) NOT NULL DEFAULT 'EA',
  brand           VARCHAR(200),
  model_ref       VARCHAR(200),
  barcode         VARCHAR(300),
  location_id     UUID REFERENCES locations(location_id),
  min_stock       NUMERIC(12,4) NOT NULL DEFAULT 0,
  max_stock       NUMERIC(12,4),
  reorder_qty     NUMERIC(12,4),
  shelf_life_months INT,
  unit_cost       NUMERIC(15,2),
  is_critical     BOOLEAN NOT NULL DEFAULT FALSE,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_parts_no ON spare_parts(part_no);
CREATE INDEX idx_parts_barcode ON spare_parts(barcode);

-- FK from wo_spare_parts_used
ALTER TABLE wo_spare_parts_used ADD CONSTRAINT fk_wo_part FOREIGN KEY (part_id) REFERENCES spare_parts(part_id);

CREATE TABLE part_inventory (
  inventory_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  part_id           UUID NOT NULL REFERENCES spare_parts(part_id) UNIQUE,
  qty_on_hand       NUMERIC(12,4) NOT NULL DEFAULT 0,
  qty_reserved      NUMERIC(12,4) NOT NULL DEFAULT 0,
  qty_available     NUMERIC(12,4) GENERATED ALWAYS AS (qty_on_hand - qty_reserved) STORED,
  last_stocktake    DATE,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE stock_batches (
  batch_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  part_id       UUID NOT NULL REFERENCES spare_parts(part_id),
  batch_no      VARCHAR(200),
  receipt_date  DATE NOT NULL,
  expiry_date   DATE,
  qty_received  NUMERIC(12,4) NOT NULL,
  qty_remaining NUMERIC(12,4) NOT NULL,
  unit_cost     NUMERIC(15,2),
  supplier_id   UUID REFERENCES suppliers(supplier_id),
  po_no         VARCHAR(200),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE stock_transactions (
  tx_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tx_no         VARCHAR(50) UNIQUE,
  type          stock_tx_type NOT NULL,
  part_id       UUID NOT NULL REFERENCES spare_parts(part_id),
  batch_id      UUID REFERENCES stock_batches(batch_id),
  qty           NUMERIC(12,4) NOT NULL,
  unit_cost     NUMERIC(15,2),
  total_cost    NUMERIC(15,2),
  reference_id  UUID,               -- WO ID or PM WO ID
  reference_no  VARCHAR(200),
  notes         TEXT,
  performed_by  UUID REFERENCES users(user_id),
  performed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stock_tx_part ON stock_transactions(part_id, performed_at DESC);

CREATE TABLE part_machine_map (
  map_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  part_id       UUID NOT NULL REFERENCES spare_parts(part_id),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id),
  is_critical   BOOLEAN NOT NULL DEFAULT FALSE,
  qty_per_machine NUMERIC(12,4),
  notes         TEXT,
  UNIQUE (part_id, machine_id)
);

CREATE TABLE part_kits (
  kit_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  kit_no        VARCHAR(100) UNIQUE NOT NULL,
  kit_name      VARCHAR(300) NOT NULL,
  description   TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE part_kit_items (
  kit_item_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  kit_id        UUID NOT NULL REFERENCES part_kits(kit_id) ON DELETE CASCADE,
  part_id       UUID NOT NULL REFERENCES spare_parts(part_id),
  qty           NUMERIC(12,4) NOT NULL DEFAULT 1,
  UNIQUE (kit_id, part_id)
);

CREATE TABLE purchase_requests (
  pr_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  pr_no         VARCHAR(50) UNIQUE NOT NULL,
  part_id       UUID NOT NULL REFERENCES spare_parts(part_id),
  qty_requested NUMERIC(12,4) NOT NULL,
  urgency       wo_priority DEFAULT 'medium',
  reason        TEXT,
  status        VARCHAR(50) DEFAULT 'draft',   -- draft, submitted, approved, ordered, received
  auto_generated BOOLEAN NOT NULL DEFAULT FALSE,
  requested_by  UUID REFERENCES users(user_id),
  approved_by   UUID REFERENCES users(user_id),
  supplier_id   UUID REFERENCES suppliers(supplier_id),
  po_no         VARCHAR(200),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ASL (also stored via suppliers.is_approved flag)
CREATE TABLE part_supplier_map (
  map_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  part_id       UUID NOT NULL REFERENCES spare_parts(part_id),
  supplier_id   UUID NOT NULL REFERENCES suppliers(supplier_id),
  supplier_part_no VARCHAR(200),
  lead_time_days INT,
  unit_cost     NUMERIC(15,2),
  is_preferred  BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (part_id, supplier_id)
);

-- =============================================================================
-- MODULE 8: ANALYTICS & AI
-- =============================================================================

CREATE TABLE sensor_readings (
  reading_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id),
  parameter     VARCHAR(200) NOT NULL,
  value         NUMERIC(15,6) NOT NULL,
  unit          VARCHAR(50),
  baseline_min  NUMERIC(15,6),
  baseline_max  NUMERIC(15,6),
  z_score       NUMERIC(8,4),
  is_anomaly    BOOLEAN NOT NULL DEFAULT FALSE,
  recorded_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sensor_machine_time ON sensor_readings(machine_id, recorded_at DESC);

CREATE TABLE ai_predictions (
  pred_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  machine_id    UUID NOT NULL REFERENCES machines(machine_id),
  pred_type     VARCHAR(100) NOT NULL,    -- 'failure_risk', 'part_demand', 'replacement'
  result_json   JSONB NOT NULL,
  confidence    NUMERIC(5,4),
  action_plan   TEXT,
  generated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_acknowledged BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE scheduled_reports (
  report_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  report_name   VARCHAR(300) NOT NULL,
  report_type   VARCHAR(100) NOT NULL,
  schedule_cron VARCHAR(100),
  output_path   TEXT,
  last_run_at   TIMESTAMPTZ,
  next_run_at   TIMESTAMPTZ,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_by    UUID REFERENCES users(user_id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MODULE 9: WORKFORCE
-- =============================================================================

CREATE TABLE technician_profiles (
  profile_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(user_id) UNIQUE,
  skill_tags    TEXT[],
  experience_years NUMERIC(4,1),
  trade_cert    VARCHAR(200),
  is_available  BOOLEAN NOT NULL DEFAULT TRUE,
  overtime_hrs_week NUMERIC(6,2) DEFAULT 0,
  zone_location VARCHAR(200),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE tech_certifications (
  cert_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id    UUID NOT NULL REFERENCES technician_profiles(profile_id),
  cert_name     VARCHAR(300) NOT NULL,
  cert_no       VARCHAR(200),
  issued_date   DATE,
  expiry_date   DATE,
  file_path     TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE gamification_scores (
  score_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(user_id) UNIQUE,
  total_points  INT NOT NULL DEFAULT 0,
  wo_completed  INT NOT NULL DEFAULT 0,
  avg_rating    NUMERIC(3,2),
  on_time_rate  NUMERIC(5,4),
  current_badge VARCHAR(100),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- APP SETTINGS
-- =============================================================================

CREATE TABLE app_settings (
  setting_key   VARCHAR(200) PRIMARY KEY,
  setting_value TEXT,
  description   TEXT,
  updated_by    UUID REFERENCES users(user_id),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Add FK from machines to factory_floors
-- =============================================================================
ALTER TABLE machines ADD CONSTRAINT fk_machine_floor FOREIGN KEY (floor_id) REFERENCES factory_floors(floor_id);

-- =============================================================================
-- VIEWS
-- =============================================================================

-- Machine dashboard view with latest status
CREATE VIEW v_machine_dashboard AS
SELECT
  m.machine_id,
  m.machine_no,
  m.brand,
  m.model,
  m.serial_no,
  m.status,
  m.location,
  mc.name AS category_name,
  d.dept_name,
  mh_s1.status AS stage1_status,
  mh_s2.status AS stage2_status,
  mh_s3.status AS stage3_status,
  m.handover_completed,
  COALESCE(mrh.cumulative_hours, 0) AS total_running_hours,
  m.installation_date,
  m.is_active
FROM machines m
LEFT JOIN machine_categories mc ON mc.category_id = m.category_id
LEFT JOIN departments d ON d.dept_id = m.dept_id
LEFT JOIN machine_handover mh_s1 ON mh_s1.machine_id = m.machine_id AND mh_s1.stage = 'stage1'
LEFT JOIN machine_handover mh_s2 ON mh_s2.machine_id = m.machine_id AND mh_s2.stage = 'stage2'
LEFT JOIN machine_handover mh_s3 ON mh_s3.machine_id = m.machine_id AND mh_s3.stage = 'stage3'
LEFT JOIN LATERAL (
  SELECT cumulative_hours FROM machine_running_hours
  WHERE machine_id = m.machine_id ORDER BY recorded_date DESC LIMIT 1
) mrh ON TRUE;

-- Open work orders summary
CREATE VIEW v_open_work_orders AS
SELECT
  wo.wo_id, wo.wo_no, wo.type, wo.priority, wo.status,
  wo.title, wo.reported_at, wo.sla_due_at,
  m.machine_no, m.location,
  u_rep.full_name AS reported_by_name,
  u_lead.full_name AS assigned_lead_name,
  CASE WHEN wo.sla_due_at < NOW() AND wo.status NOT IN ('completed','closed','cancelled')
       THEN TRUE ELSE FALSE END AS is_overdue
FROM work_orders wo
LEFT JOIN machines m ON m.machine_id = wo.machine_id
LEFT JOIN users u_rep ON u_rep.user_id = wo.reported_by
LEFT JOIN users u_lead ON u_lead.user_id = wo.assigned_lead
WHERE wo.status NOT IN ('closed', 'cancelled');

-- =============================================================================
-- INDEXES (additional performance)
-- =============================================================================

CREATE INDEX idx_machines_active ON machines(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_pm_plans_due ON pm_plans(next_due) WHERE is_active = TRUE;
CREATE INDEX idx_calibration_due ON measuring_tools(calibration_due);
CREATE INDEX idx_permit_active ON work_permits(status, validity_end) WHERE status = 'active';
CREATE INDEX idx_stock_low ON part_inventory(qty_available);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE machines IS 'Master registry of all factory machines and equipment';
COMMENT ON TABLE machine_handover IS '3-stage digital handover process for new machine acceptance';
COMMENT ON TABLE work_orders IS 'Central work order management for all repair, modification, and PM tasks';
COMMENT ON TABLE work_permits IS 'E-Work Permit system for high-risk jobs (hot work, confined space, etc.)';
COMMENT ON TABLE audit_log IS 'Immutable audit trail of all data changes with user + IP';
COMMENT ON TABLE wo_knowledge_base IS 'Searchable knowledge base of past problem/solution pairs for auto-suggestion';
