-- =============================================================================
-- MASAPP Seed Data
-- Run AFTER schema.sql
-- =============================================================================

-- Departments
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  ('00000000-0000-0000-0000-000000000001', 'MAINT', 'แผนกซ่อมบำรุง'),
  ('00000000-0000-0000-0000-000000000002', 'PROD',  'แผนกผลิต'),
  ('00000000-0000-0000-0000-000000000003', 'QA',    'แผนกควบคุมคุณภาพ'),
  ('00000000-0000-0000-0000-000000000004', 'SAFETY','แผนกความปลอดภัย'),
  ('00000000-0000-0000-0000-000000000005', 'STORE', 'คลังสินค้า');

-- Admin user (password: Admin@1234)
INSERT INTO users (user_id, employee_no, username, full_name, email, role, dept_id, password_hash) VALUES
  ('00000000-0000-0000-0001-000000000001',
   'EMP001', 'admin', 'System Administrator', 'admin@masapp.local',
   'admin', '00000000-0000-0000-0000-000000000001',
   -- SHA-256("Admin@1234")
   encode(sha256('Admin@1234'::bytea), 'hex')
  );

-- Note: The actual hash above is SHA-256("password")
-- Change immediately upon first login!

-- Machine Categories
INSERT INTO machine_categories (category_id, code, name) VALUES
  ('00000000-0000-0000-0002-000000000001', 'ELECTRICAL', 'ระบบไฟฟ้า'),
  ('00000000-0000-0000-0002-000000000002', 'MECHANICAL', 'เครื่องจักรกล'),
  ('00000000-0000-0000-0002-000000000003', 'HYDRAULIC',  'ระบบไฮดรอลิก'),
  ('00000000-0000-0000-0002-000000000004', 'PNEUMATIC',  'ระบบลม'),
  ('00000000-0000-0000-0002-000000000005', 'CONVEYOR',   'สายพานลำเลียง'),
  ('00000000-0000-0000-0002-000000000006', 'HVAC',       'ระบบปรับอากาศ'),
  ('00000000-0000-0000-0002-000000000007', 'UTILITY',    'สาธารณูปโภค'),
  ('00000000-0000-0000-0002-000000000008', 'PRODUCTION', 'เครื่องจักรผลิต');

-- Spare Part Categories
INSERT INTO spare_part_categories (cat_id, code, name) VALUES
  ('00000000-0000-0000-0003-000000000001', 'BEARING',   'ลูกปืน'),
  ('00000000-0000-0000-0003-000000000002', 'BELT',      'สายพาน'),
  ('00000000-0000-0000-0003-000000000003', 'ELECTRICAL','อะไหล่ไฟฟ้า'),
  ('00000000-0000-0000-0003-000000000004', 'FILTER',    'ไส้กรอง'),
  ('00000000-0000-0000-0003-000000000005', 'SEAL',      'ซีล & โอริง'),
  ('00000000-0000-0000-0003-000000000006', 'LUBRICANT', 'น้ำมันหล่อลื่น'),
  ('00000000-0000-0000-0003-000000000007', 'FASTENER',  'น็อต & สลักเกลียว'),
  ('00000000-0000-0000-0008-000000000008', 'OTHER',     'อื่นๆ');

-- App settings defaults
INSERT INTO app_settings (setting_key, setting_value, description) VALUES
  ('app.company_name', 'โรงงานตัวอย่าง จำกัด', 'ชื่อบริษัท'),
  ('app.logo_path', '', 'Path to company logo'),
  ('wo.auto_sla_critical_hrs', '2', 'SLA hours for critical WO'),
  ('wo.auto_sla_high_hrs', '8', 'SLA hours for high priority WO'),
  ('wo.auto_sla_medium_hrs', '24', 'SLA hours for medium priority WO'),
  ('wo.auto_sla_low_hrs', '72', 'SLA hours for low priority WO'),
  ('stock.low_stock_alert_enabled', 'true', 'Enable low stock alerts'),
  ('permit.require_gas_test_confined', 'true', 'Require gas test for confined space'),
  ('am.compliance_target_pct', '95', 'Target AM compliance %');
