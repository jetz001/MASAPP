-- =============================================================================
-- MASAPP Seed Data (SQLite) — v2 with full sample data
-- =============================================================================

-- Departments
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  ('00000000-0000-0000-0000-000000000001', 'MAINT', 'แผนกซ่อมบำรุง'),
  ('00000000-0000-0000-0000-000000000002', 'PROD',  'แผนกผลิต'),
  ('00000000-0000-0000-0000-000000000003', 'QA',    'แผนกควบคุมคุณภาพ'),
  ('00000000-0000-0000-0000-000000000004', 'SAFETY','แผนกความปลอดภัย'),
  ('00000000-0000-0000-0000-000000000005', 'STORE', 'คลังสินค้า');

-- Users (theme_preference included)
INSERT OR REPLACE INTO users (user_id, employee_no, username, full_name, email, role, dept_id, password_hash, approval_pin_hash, theme_preference) VALUES
  ('00000000-0000-0000-0001-000000000001','EMP001','admin','System Administrator','admin@masapp.local','admin','00000000-0000-0000-0000-000000000001','$2a$10$kCWRye5Sa.VdECJCmMu9nuPGOdnpJy.xBDpoJzR9ooMCHGNMGMXEe','$2a$10$rldt6VRimShGDHOZY8HVEOwUl/1Cg8DfsDA5jZ3DcsqtWtf5bm7p2','dark'),
  ('00000000-0000-0000-0001-000000000002','EMP002','somchai','สมชาย มีทักษะ','somchai@masapp.local','technician','00000000-0000-0000-0000-000000000001','$2a$10$VIYSP4OrO50rq94hTRYa1uQGVnnqZYYfwL/72DAnqrai6cHJEWBBW','$2a$10$rldt6VRimShGDHOZY8HVEOwUl/1Cg8DfsDA5jZ3DcsqtWtf5bm7p2','dark'),
  ('00000000-0000-0000-0001-000000000003','EMP003','siriporn','สิริพร วิศวกร','siriporn@masapp.local','engineer','00000000-0000-0000-0000-000000000001','$2a$10$VIYSP4OrO50rq94hTRYa1uQGVnnqZYYfwL/72DAnqrai6cHJEWBBW','$2a$10$rldt6VRimShGDHOZY8HVEOwUl/1Cg8DfsDA5jZ3DcsqtWtf5bm7p2','light'),
  ('00000000-0000-0000-0001-000000000004','EMP004','prasit','ประสิทธิ์ ช่างไฟ','prasit@masapp.local','technician','00000000-0000-0000-0000-000000000001','$2a$10$VIYSP4OrO50rq94hTRYa1uQGVnnqZYYfwL/72DAnqrai6cHJEWBBW','$2a$10$rldt6VRimShGDHOZY8HVEOwUl/1Cg8DfsDA5jZ3DcsqtWtf5bm7p2','dark'),
  ('00000000-0000-0000-0001-000000000005','EMP005','wanida','วนิดา ผู้ปฏิบัติ','wanida@masapp.local','operator','00000000-0000-0000-0000-000000000002','$2a$10$VIYSP4OrO50rq94hTRYa1uQGVnnqZYYfwL/72DAnqrai6cHJEWBBW',NULL,'dark'),
  ('00000000-0000-0000-0001-000000000006','EMP006','chaiyapol','ชัยพล จป.','chaiyapol@masapp.local','safety','00000000-0000-0000-0000-000000000004','$2a$10$VIYSP4OrO50rq94hTRYa1uQGVnnqZYYfwL/72DAnqrai6cHJEWBBW','$2a$10$rldt6VRimShGDHOZY8HVEOwUl/1Cg8DfsDA5jZ3DcsqtWtf5bm7p2','dark'),
  ('00000000-0000-0000-0001-000000000007','EMP007','wichai','วิชัย ผู้บริหาร','wichai@masapp.local','executive','00000000-0000-0000-0000-000000000001','$2a$10$VIYSP4OrO50rq94hTRYa1uQGVnnqZYYfwL/72DAnqrai6cHJEWBBW','$2a$10$rldt6VRimShGDHOZY8HVEOwUl/1Cg8DfsDA5jZ3DcsqtWtf5bm7p2','light');

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

-- Suppliers
INSERT INTO suppliers (supplier_id, supplier_code, name, contact_name, phone, email, is_approved) VALUES
  ('00000000-SUPP-0000-0000-000000000001','SUP-001','บริษัท ซีเมนส์ (ไทย) จำกัด','คุณสมศักดิ์','02-111-1111','info@siemens.co.th',1),
  ('00000000-SUPP-0000-0000-000000000002','SUP-002','ABB Thailand','คุณมาลี','02-222-2222','info@abb.co.th',1),
  ('00000000-SUPP-0000-0000-000000000003','SUP-003','บริษัท ท็อปอะไหล่ จำกัด','คุณวีระ','02-333-3333','sale@topapart.co.th',1);

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

-- Sample Machines
INSERT INTO machines (machine_id, machine_no, asset_no, brand, model, serial_no, category_id, dept_id, location, status, installation_date, handover_completed, created_by) VALUES
  ('00000000-0000-0000-0003-000000000001','MCH-001','ASSET-001','Siemens','S7-1200','SN-001-2024','00000000-0000-0000-0002-000000000001','00000000-0000-0000-0000-000000000002','Floor 1, Zone A','normal','2024-01-15',1,'00000000-0000-0000-0001-000000000001'),
  ('00000000-0000-0000-0003-000000000002','MCH-002','ASSET-002','ABB','ACS880','SN-002-2024','00000000-0000-0000-0002-000000000001','00000000-0000-0000-0000-000000000002','Floor 1, Zone B','breakdown','2024-02-20',1,'00000000-0000-0000-0001-000000000001'),
  ('00000000-0000-0000-0003-000000000003','MCH-003','ASSET-003','Hyundai','EX220','SN-003-2023','00000000-0000-0000-0002-000000000002','00000000-0000-0000-0000-000000000002','Floor 2, Zone C','pm','2023-06-10',1,'00000000-0000-0000-0001-000000000001'),
  ('00000000-0000-0000-0003-000000000004','MCH-004','ASSET-004','Parker','PV330','SN-004-2023','00000000-0000-0000-0002-000000000003','00000000-0000-0000-0000-000000000002','Floor 1, Zone D','normal','2023-09-05',0,'00000000-0000-0000-0001-000000000001'),
  ('00000000-0000-0000-0003-000000000005','MCH-005','ASSET-005','SMC','SY7000','SN-005-2023','00000000-0000-0000-0002-000000000004','00000000-0000-0000-0000-000000000002','Floor 2, Zone A','normal','2023-11-01',1,'00000000-0000-0000-0001-000000000001');

-- Sample Machine Specs
INSERT INTO machine_specs (spec_id, machine_id, power_kw, voltage_v, current_a, frequency_hz, rpm) VALUES
  ('00000000-0000-0000-0004-000000000001','00000000-0000-0000-0003-000000000001',5.5,480,8.0,60,3600),
  ('00000000-0000-0000-0004-000000000002','00000000-0000-0000-0003-000000000002',7.5,480,12.0,60,1800),
  ('00000000-0000-0000-0004-000000000003','00000000-0000-0000-0003-000000000003',22,480,32.0,60,1500),
  ('00000000-0000-0000-0004-000000000004','00000000-0000-0000-0003-000000000004',15,350,50.0,60,2300),
  ('00000000-0000-0000-0004-000000000005','00000000-0000-0000-0003-000000000005',3.7,220,9.0,50,1450);

-- Sample Factory Layout
INSERT INTO factory_layouts (layout_id, layout_name, floor_no, width_m, height_m, created_by) VALUES
  ('00000000-0000-0000-0005-000000000001','Floor 1 - Production Area',1,50,40,'00000000-0000-0000-0001-000000000001');

-- Sample Layout Zones
INSERT INTO layout_zones (zone_id, layout_id, zone_name, x_start, y_start, x_end, y_end) VALUES
  ('00000000-0000-0000-0006-000000000001','00000000-0000-0000-0005-000000000001','Zone A - Assembly',0,0,1000,1000),
  ('00000000-0000-0000-0006-000000000002','00000000-0000-0000-0005-000000000001','Zone B - Testing',1000,0,2000,1000),
  ('00000000-0000-0000-0006-000000000003','00000000-0000-0000-0005-000000000001','Zone C - Packaging',2000,0,2500,1000),
  ('00000000-0000-0000-0006-000000000004','00000000-0000-0000-0005-000000000001','Zone D - Storage',0,1000,1250,2000);

-- Sample Machine Positions on Layout
INSERT INTO machine_positions (position_id, layout_id, machine_id, x_position, y_position) VALUES
  ('00000000-0000-0000-0007-000000000001','00000000-0000-0000-0005-000000000001','00000000-0000-0000-0003-000000000001',500,400),
  ('00000000-0000-0000-0007-000000000002','00000000-0000-0000-0005-000000000001','00000000-0000-0000-0003-000000000002',1500,400),
  ('00000000-0000-0000-0007-000000000003','00000000-0000-0000-0005-000000000001','00000000-0000-0000-0003-000000000003',2250,400),
  ('00000000-0000-0000-0007-000000000004','00000000-0000-0000-0005-000000000001','00000000-0000-0000-0003-000000000004',600,1500);

-- Sample Running Hours (for analytics)
INSERT INTO machine_running_hours (hours_id, machine_id, cumulative_hours, daily_hours, recorded_date) VALUES
  ('00000000-0000-0000-0008-000000000001','00000000-0000-0000-0003-000000000001',2400,8.0,'2026-04-15'),
  ('00000000-0000-0000-0008-000000000002','00000000-0000-0000-0003-000000000002',3200,8.0,'2026-04-15'),
  ('00000000-0000-0000-0008-000000000003','00000000-0000-0000-0003-000000000003',5100,6.5,'2026-04-15'),
  ('00000000-0000-0000-0008-000000000004','00000000-0000-0000-0003-000000000004',1800,7.0,'2026-04-15'),
  ('00000000-0000-0000-0008-000000000005','00000000-0000-0000-0003-000000000005',950,8.0,'2026-04-15');

-- Sample Work Orders
INSERT INTO work_orders (wo_id, wo_no, machine_id, status, priority, title, description, failure_symptom, assigned_to, created_by, started_at, estimated_hours) VALUES
  ('00000000-WO00-0000-0000-000000000001','WO-2026-00001','00000000-0000-0000-0003-000000000002','in_progress','high','มอเตอร์ขับสายพานเกิดเสียงดัง','มอเตอร์ ACS880 มีเสียงผิดปกติขณะสตาร์ท','เสียง vibration สูงผิดปกติ','00000000-0000-0000-0001-000000000002','00000000-0000-0000-0001-000000000003','2026-04-17 08:00:00',4.0),
  ('00000000-WO00-0000-0000-000000000002','WO-2026-00002','00000000-0000-0000-0003-000000000001','pending','normal','ตรวจสอบระบบ PLC หลังไฟดับ','ไฟดับ 30 นาที PLC alarm ติด','Alarm code E21 ขึ้น','00000000-0000-0000-0001-000000000004','00000000-0000-0000-0001-000000000003',NULL,2.0),
  ('00000000-WO00-0000-0000-000000000003','WO-2026-00003','00000000-0000-0000-0003-000000000003','completed','urgent','ไฮดรอลิกรั่ว','น้ำมันไฮดรอลิกรั่วที่ cylinder seal','น้ำมันหยดออกมาที่พื้น','00000000-0000-0000-0001-000000000002','00000000-0000-0000-0001-000000000001','2026-04-10 09:00:00',6.0);

-- Sample Spare Parts
INSERT INTO spare_parts (part_id, part_code, part_name, supplier_id, category, unit_cost, reorder_level) VALUES
  ('00000000-PART-0000-0000-000000000001','PRT-001','Bearing SKF 6205','00000000-SUPP-0000-0000-000000000003','Bearing',350.0,10),
  ('00000000-PART-0000-0000-000000000002','PRT-002','Oil Seal 35x52x10','00000000-SUPP-0000-0000-000000000003','Seal',120.0,20),
  ('00000000-PART-0000-0000-000000000003','PRT-003','Hydraulic Oil 46 (20L)','00000000-SUPP-0000-0000-000000000003','Lubricant',1800.0,3),
  ('00000000-PART-0000-0000-000000000004','PRT-004','V-Belt A42','00000000-SUPP-0000-0000-000000000003','Belt',280.0,5),
  ('00000000-PART-0000-0000-000000000005','PRT-005','Contactor Siemens 3TF','00000000-SUPP-0000-0000-000000000001','Electrical',1200.0,3),
  ('00000000-PART-0000-0000-000000000006','PRT-006','Fuse 10A 415V','00000000-SUPP-0000-0000-000000000001','Electrical',45.0,50);

-- Sample Inventory
INSERT INTO spare_parts_inventory (inventory_id, part_id, quantity_on_hand, quantity_reserved, location) VALUES
  ('00000000-INV0-0000-0000-000000000001','00000000-PART-0000-0000-000000000001',25,2,'Rack A-01'),
  ('00000000-INV0-0000-0000-000000000002','00000000-PART-0000-0000-000000000002',40,0,'Rack A-02'),
  ('00000000-INV0-0000-0000-000000000003','00000000-PART-0000-0000-000000000003',2,0,'Tank Room'),
  ('00000000-INV0-0000-0000-000000000004','00000000-PART-0000-0000-000000000004',8,1,'Rack B-01'),
  ('00000000-INV0-0000-0000-000000000005','00000000-PART-0000-0000-000000000005',4,0,'Rack C-01'),
  ('00000000-INV0-0000-0000-000000000006','00000000-PART-0000-0000-000000000006',120,0,'Rack C-02');

-- Sample PM Plans
INSERT INTO pm_am_plans (plan_id, machine_id, plan_type, plan_code, plan_name, frequency_days, estimated_hours, created_by) VALUES
  ('00000000-PLAN-0000-0000-000000000001','00000000-0000-0000-0003-000000000001','PM','PM-MCH001-W','PM รายสัปดาห์ MCH-001',7,2.0,'00000000-0000-0000-0001-000000000003'),
  ('00000000-PLAN-0000-0000-000000000002','00000000-0000-0000-0003-000000000002','PM','PM-MCH002-M','PM รายเดือน MCH-002',30,4.0,'00000000-0000-0000-0001-000000000003'),
  ('00000000-PLAN-0000-0000-000000000003','00000000-0000-0000-0003-000000000003','AM','AM-MCH003-D','AM รายวัน MCH-003',1,0.5,'00000000-0000-0000-0001-000000000003');

-- Sample PM Schedules
INSERT INTO pm_am_schedules (schedule_id, plan_id, scheduled_date, assigned_to, status) VALUES
  ('00000000-SCH0-0000-0000-000000000001','00000000-PLAN-0000-0000-000000000001','2026-04-18','00000000-0000-0000-0001-000000000002','pending'),
  ('00000000-SCH0-0000-0000-000000000002','00000000-PLAN-0000-0000-000000000002','2026-04-10','00000000-0000-0000-0001-000000000002','overdue'),
  ('00000000-SCH0-0000-0000-000000000003','00000000-PLAN-0000-0000-000000000003','2026-04-18','00000000-0000-0000-0001-000000000005','pending');

-- Sample PM Tasks
INSERT INTO pm_am_tasks (task_id, plan_id, task_order, task_name, task_type, is_critical) VALUES
  ('00000000-TASK-0000-0000-000000000001','00000000-PLAN-0000-0000-000000000001',1,'ทำความสะอาดตัวเครื่อง','clean',0),
  ('00000000-TASK-0000-0000-000000000002','00000000-PLAN-0000-0000-000000000001',2,'ตรวจสอบ vibration','inspect',1),
  ('00000000-TASK-0000-0000-000000000003','00000000-PLAN-0000-0000-000000000001',3,'ขันแน่น bolt ยึดมอเตอร์','tighten',1),
  ('00000000-TASK-0000-0000-000000000004','00000000-PLAN-0000-0000-000000000002',1,'เปลี่ยนน้ำมัน gear box','replace',1),
  ('00000000-TASK-0000-0000-000000000005','00000000-PLAN-0000-0000-000000000003',1,'ทำความสะอาดฝุ่นรอบเครื่อง','clean',0),
  ('00000000-TASK-0000-0000-000000000006','00000000-PLAN-0000-0000-000000000003',2,'ตรวจสอบ emergency stop','inspect',1);

-- Sample Technician Skills
INSERT INTO technician_skills (skill_id, technician_id, skill_name, proficiency_level, certified) VALUES
  ('00000000-SKL0-0000-0000-000000000001','00000000-0000-0000-0001-000000000002','ระบบไฟฟ้า','expert',1),
  ('00000000-SKL0-0000-0000-000000000002','00000000-0000-0000-0001-000000000002','PLC Programming','intermediate',0),
  ('00000000-SKL0-0000-0000-000000000003','00000000-0000-0000-0001-000000000004','ระบบไฮดรอลิก','expert',1),
  ('00000000-SKL0-0000-0000-000000000004','00000000-0000-0000-0001-000000000004','ระบบลม','intermediate',1);

-- Sample Work Permits
INSERT INTO work_permits (permit_id, permit_no, permit_type, machine_id, description, duration_hours, requestor, requester_name, status) VALUES
  ('00000000-PRMT-0000-0000-000000000001','WP-2026-00001','hot_work','00000000-0000-0000-0003-000000000002','งานเชื่อมซ่อมโครงสร้างรองมอเตอร์',4,'00000000-0000-0000-0001-000000000002','สมชาย มีทักษะ','pending'),
  ('00000000-PRMT-0000-0000-000000000002','WP-2026-00002','electrical','00000000-0000-0000-0003-000000000001','งานเดินสายไฟ panel ใหม่',8,'00000000-0000-0000-0001-000000000004','ประสิทธิ์ ช่างไฟ','approved');
