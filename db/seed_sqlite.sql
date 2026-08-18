-- =============================================================================
-- MASAPP Seed Data (SQLite)
-- =============================================================================

-- Departments
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  ('00000000-0000-0000-0000-000000000001', 'MAINT', 'แผนกซ่อมบำรุง'),
  ('00000000-0000-0000-0000-000000000002', 'PROD',  'แผนกผลิต'),
  ('00000000-0000-0000-0000-000000000003', 'QA',    'แผนกควบคุมคุณภาพ'),
  ('00000000-0000-0000-0000-000000000004', 'SAFETY','แผนกความปลอดภัย'),
  ('00000000-0000-0000-0000-000000000005', 'STORE', 'คลังสินค้า');

-- Admin user (password: Admin@1234)
INSERT OR REPLACE INTO users (user_id, employee_no, username, full_name, email, role, dept_id, password_hash, approval_pin_hash, theme_preference) VALUES
  ('00000000-0000-0000-0001-000000000001','EMP001','admin','System Administrator','admin@masapp.local','admin','00000000-0000-0000-0000-000000000001','bc78e58d55cde1346e68f8e5fe588dedf62fa457aa646a500a53347faff6ee24','8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92','dark');

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
  ('am.compliance_target_pct', '95', 'Target AM compliance %'),
  ('ai_provider', 'gemini', 'Active AI provider'),
  ('ai_model_gemini', 'gemini-1.5-flash-latest', 'Google Gemini model'),
  ('ai_model_openai', 'gpt-4o-mini', 'OpenAI model'),
  ('ai_model_claude', 'claude-3-5-haiku-latest', 'Anthropic Claude model'),
  ('ai_model_deepseek', 'deepseek-chat', 'DeepSeek model'),
  ('ai_model_grok', 'grok-beta', 'xAI Grok model'),
  ('ai_model_mistral', 'mistral-small-latest', 'Mistral model'),
  ('ai_model_ollama', 'llama3.1:8b', 'Ollama model'),
  ('ai_base_url_openai', 'https://api.openai.com/v1', 'OpenAI base URL'),
  ('ai_base_url_claude', 'https://api.anthropic.com/v1', 'Anthropic Claude base URL'),
  ('ai_base_url_deepseek', 'https://api.deepseek.com', 'DeepSeek base URL'),
  ('ai_base_url_grok', 'https://api.x.ai/v1', 'xAI Grok base URL'),
  ('ai_base_url_mistral', 'https://api.mistral.ai/v1', 'Mistral base URL'),
  ('ai_base_url_ollama', 'http://127.0.0.1:11434', 'Ollama base URL'),
  ('brave_search_api_key', '', 'Brave Search API key for external web search'),
  ('assets.storage_mode', 'managed_storage', 'Store uploaded files in MASAPP managed storage beside the database'),
  ('assets.storage_root_strategy', 'db_relative_storage', 'Resolve managed storage relative to the selected database path'),
  ('file_assets_legacy_storage_migrated_v1', 'true', 'Fresh seed databases do not require legacy asset path migration');
