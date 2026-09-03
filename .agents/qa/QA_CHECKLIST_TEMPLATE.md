# MASAPP - แบบฟอร์มเช็คลิสต์ตรวจสอบคุณภาพระบบ (7-Dimension QA Checklist)

> **คำแนะนำสำหรับ AI Agent & QA Engineer**:  
> ก่อนส่งมอบงานหรือสรุปผลการพัฒนาฟีเจอร์ใดๆ ใน MASAPP ให้ตรวจสอบความพร้อมตามเกณฑ์ทั้ง 7 มิติด้านล่างนี้ โดยติ๊กเครื่องหมาย `[x]` และระบุข้อสังเกตหรือผลการทดสอบลงในช่องบันทึก

---

## มิติที่ 1: ฐานข้อมูลและการย้ายข้อมูล (Database & Migrations)
- [ ] **1.1 Idempotent Schema Creation**:
  - เมื่อเปิดฐานข้อมูลใหม่ (`Fresh DB`) ตารางทั้งหมดต้องถูกสร้างขึ้นครบถ้วนโดยไม่มี error
  - รัน `DbInitializer.initializeDatabase()` ซ้ำบนฐานข้อมูลเดิม ต้องทำงานผ่าน ไม่พังจาก Duplicate Column หรือ Conflict
- [ ] **1.2 Migration Integrity**:
  - การเพิ่ม Column หรือ Table ใหม่ต้องใช้คำสั่ง `IF NOT EXISTS` หรือตรวจสอบผ่าน `PRAGMA table_info` ก่อนรัน `ALTER TABLE`
  - ตรวจสอบ Foreign Key ไม่ให้ชี้ไปยังตารางชั่วคราวหรือตารางเก่า (เช่น `work_orders_old`)
- [ ] **1.3 Seed Data Verification**:
  - ตรวจสอบว่าไฟล์ `db/seed_sqlite.sql` และ `DbInitializer._seedInitialData` มีข้อมูลตั้งต้นสอดคล้องกัน (เช่น แผนก, บทบาทผู้ใช้, เวกเตอร์ระบบ)
- [ ] **1.4 Network Share & Path Resilience**:
  - ระบบรองรับทั้ง Local Path (`D:\...`) และ Network UNC Path (`\\server\share\masapp.db`) โดยไม่เกิด Crash

*บันทึกผลการตรวจสอบมิติที่ 1*:  
`[ระบุรายละเอียดผลการทดสอบ เช่น test/db_schema_seed_test.dart ผ่าน 100%]`

---

## มิติที่ 2: การจัดการไฟล์แนบ (Managed Storage & File Assets)
- [ ] **2.1 Zero Hardcoded Absolute Paths**:
  - **ห้าม** บันทึก Path แบบตายตัว (เช่น `C:\Users\...` หรือ `D:\DEV\...`) ลงในตารางข้อมูล SQLite
  - ทุกไฟล์แนบต้องบันทึกผ่าน `AttachmentStorageService`
- [ ] **2.2 DB-Relative Directory Structure**:
  - ไฟล์แนบต้องถูกเก็บในโฟลเดอร์ `storage/` ที่อยู่ติดกับไฟล์ฐานข้อมูล `.db` ตามโครงสร้าง `storage/{moduleType}/{entityId}/original/`
- [ ] **2.3 Metadata Registration (`file_assets`)**:
  - ข้อมูลไฟล์ต้องถูกลงทะเบียนในตาราง `file_assets` ครบถ้วน (ขนาดไฟล์, MIME type, ความกว้าง, ความสูง, จำนวนหน้า)
- [ ] **2.4 Image & PDF Derivatives**:
  - ไฟล์รูปภาพและ PDF มีการสร้าง Preview (`_preview.png`) และ Thumbnail (`_thumb.png`) อย่างถูกต้อง ไม่เกิด Memory Leak

*บันทึกผลการตรวจสอบมิติที่ 2*:  
`[ระบุรายละเอียดผลการทดสอบ เช่น test/unit/storage_and_assets_test.dart ผ่าน]`

---

## มิติที่ 3: กระบวนการทางธุรกิจหลัก (Core Business Workflows)
- [ ] **3.1 Work Order Lifecycle**:
  - การเปลี่ยนสถานะใบสั่งซ่อม (`pending` -> `approved` -> `inProgress` -> `completed` / `cancelled` / `rejected` / `outsourced`) ถูกต้องตามสิทธิ์ผู้ใช้งาน (RBAC)
  - ข้อมูลเวลาเริ่มต้น (`started_at`), เวลาเสร็จสิ้น (`completed_at`) และผู้รับผิดชอบ (`assigned_to`) ถูกบันทึกครบถ้วน
- [ ] **3.2 Machine Handover & Intake**:
  - การบันทึกทะเบียนเครื่องจักรใหม่ และการตรวจรับมอบเครื่องจักรพร้อมรูปถ่ายทำงานได้ราบรื่น
- [ ] **3.3 Spare Parts & Inventory**:
  - การเบิก-จ่ายอะไหล่มีการตัดสต็อกถูกต้อง และบันทึกลงประวัติ Stock Card
- [ ] **3.4 Tools & Calibration**:
  - ระบบทะเบียนเครื่องมือ การยืม-คืน และการแจ้งเตือนวันหมดอายุการสอบเทียบ (Calibration Date) ทำงานถูกต้อง

*บันทึกผลการตรวจสอบมิติที่ 3*:  
`[ระบุผลการตรวจสอบ เช่น test/unit/work_order_models_test.dart ผ่าน]`

---

## มิติที่ 4: การออกเอกสารและรายงาน (Presentation & Reporting)
- [ ] **4.1 Slide Presentation Studio (Landscape A4)**:
  - ขนาดหน้าเอกสารต้องเป็นแนวนอน `PdfPageFormat.a4.landscape`
  - การตัดขึ้นหน้าใหม่ (Page Break) สะอาด เนื้อหาไม่ทับซ้อนหรือล้นขอบกระดาษ
- [ ] **4.2 Thai Font & Encoding**:
  - ข้อความภาษาไทย (สระ วรรณยุกต์) แสดงผลถูกต้องในไฟล์ PDF ไม่เป็นตัวสี่เหลี่ยมหรือภาษาต่างดาว (รองรับ Sarabun / THSarabunNew)
- [ ] **4.3 Work Order & Work Permit PDF**:
  - เอกสารใบแจ้งซ่อม, ใบขออนุญาตทำงาน (Work Permit), ใบผ่านประตู (Gate Pass) และแบบฟอร์ม 8D Report แสดงลายเซ็นและหัวกระดาษบริษัทครบถ้วน
- [ ] **4.4 1-Click System Viewer**:
  - ปุ่ม `[เปิด PDF ทันที]` สามารถเรียกโปรแกรมอ่าน PDF เริ่มต้นของ Windows ขึ้นมาแสดงผลได้จริง

*บันทึกผลการตรวจสอบมิติที่ 4*:  
`[ระบุผลการตรวจสอบการ Render PDF]`

---

## มิติที่ 5: หน้าจอ Canvas & วิศวกรรมการผลิต (Line Balancing Studio)
- [ ] **5.1 Takt Time & Bottleneck Calculation**:
  - การคำนวณ Takt Time, Cycle Time รวม, Bottleneck Station, Line Efficiency (E) และ Balance Delay (d) ให้ผลลัพธ์ที่ถูกต้องตามสูตรวิศวกรรม
- [ ] **5.2 Interactive Node Canvas**:
  - การลากวางสถานีงาน (Workstation Nodes), การเชื่อมโยงกระบวนการ (Precedence Arrows) ตอบสนองลื่นไหล ไม่มีอาการค้างหรือ Frame Drop
- [ ] **5.3 State Purity in Riverpod**:
  - การสลับหน้าจอไปมาต้องไม่ทำให้ State บนผังเกิด Side-effect หรือข้อมูลสูญหาย

*บันทึกผลการตรวจสอบมิติที่ 5*:  
`[ระบุผลการตรวจสอบ State และการคำนวณ Line Balancing]`

---

## มิติที่ 6: ระบบผู้ช่วย AI และการค้นหาข้อมูล (AI & Vector Exploration)
- [ ] **6.1 DB-First Exploration**:
  - AI ต้องค้นหาข้อมูลจากฐานข้อมูล SQLite และ Knowledge Vectors ก่อนเป็นอันดับแรก ก่อนจะค้นหาจากภายนอก
- [ ] **6.2 External Search Grounding**:
  - เมื่อมีการดึงข้อมูลจากอินเทอร์เน็ต ต้องมีป้ายกำกับแหล่งที่มา (Metadata Labels) ชัดเจน ไม่ปะปนกับข้อมูลในโรงงาน
- [ ] **6.3 Multi-Provider Resilience**:
  - รองรับการสลับผู้ให้บริการโมเดล (Gemini, OpenAI, Claude, DeepSeek, Ollama) โดยไม่เกิด unhandled crash หาก API Key ไม่สมบูรณ์หรือ Offline

*บันทึกผลการตรวจสอบมิติที่ 6*:  
`[ระบุผลการตรวจสอบ AI context และ Vector Query]`

---

## มิติที่ 7: ความเสถียรบน Windows Desktop & UI/UX (Desktop Robustness)
- [ ] **7.1 Window Resizing & Layout Overflow**:
  - หน้าจอรองรับการขยาย/ย่อหน้าต่าง (Window Resizing) ได้อย่างยืดหยุ่น โดยไม่เกิดข้อผิดพลาด RenderFlex Overflow (แถบเหลืองดำ)
- [ ] **7.2 Dialog & File Picker Null Safety**:
  - เมื่อผู้ใช้งานกดยกเลิก Dialog หรือกดยกเลิกหน้าต่างเลือกไฟล์ (`FilePicker` ส่งกลับ `null`) แอปต้องไม่ Crash
- [ ] **7.3 UTF-8 Character Encoding**:
  - ทุกไฟล์ Source Code, ข้อมูลใน Database และการ Export ไฟล์ข้อความ ต้องใช้ Encoding แบบ UTF-8
- [ ] **7.4 Automated Pipeline Passing**:
  - รัน `powershell -ExecutionPolicy Bypass -File .\scripts\run_qa.ps1` ต้องได้สถานะ `QA RESULT: ALL CHECKS PASSED` และ Exit Code เป็น `0`

*บันทึกผลการตรวจสอบมิติที่ 7*:  
`[ระบุผลการรัน run_qa.ps1]`

---

## มิติที่ 8: การทดสอบเชิงสำรวจและความคิดสร้างสรรค์ (Creative, Chaos & Exploratory Testing)
> **เปิดโอกาสให้ AI ใช้ความคิดสร้างสรรค์และจินตนาการสถานการณ์เหนือความคาดหมาย (Think Outside the Box)**  
> เพื่อค้นหาช่องโหว่หรือบั๊กแฝงที่การทดสอบตามกรอบปกติอาจตรวจไม่พบ

- [ ] **8.1 Extreme Boundary & Weird Input Injection**:
  - ทดลองกรอกข้อมูลสุดโต่ง เช่น ตัวเลขติดลบ, ทศนิยมยาวเหยียด, สตริงขนาดยักษ์, สัญลักษณ์พิเศษ (`<script>`, SQL injection strings, Emoji ผสมอักษรไทย)
  - ตรวจสอบว่าระบบ Sanitizes ข้อมูล หรือแจ้งเตือนผู้ใช้อย่างสุภาพโดยไม่เกิด Unhandled Crash
- [ ] **8.2 Stress, Rapid Action & Button Mashing (Race Conditions)**:
  - จำลองพฤติกรรมผู้ใช้กดย้ำปุ่มบันทึกหรือปุ่ม Export เร็วๆ ซ้ำๆ (Double/Triple Click) ว่าระบบมี Debounce ป้องกันข้อมูลเบิ้ลหรือไม่
  - การเปิด-ปิดหน้าต่างซ้อนกันอย่างรวดเร็ว หรือการกดเปลี่ยนแท็บไปมาระหว่างที่ข้อมูลกำลังโหลด
- [ ] **8.3 Chaos & Fault Injection (Disaster Scenarios)**:
  - จำลองไฟล์ฐานข้อมูลหรือโฟลเดอร์ `storage/` ถูกตั้งค่าเป็น Read-Only หรือถูกเปิดล็อกค้างไว้โดยโปรแกรมภายนอก
  - จำลองการตัดการเชื่อมต่อระหว่างเขียนไฟล์แนบ หรือพื้นที่ฮาร์ดดิสก์เต็ม
- [ ] **8.4 Factory Floor & Ergonomic Simulation**:
  - จำลองสถานการณ์ช่างในโรงงานใส่ถุงมือหรือใช้หน้าจอสัมผัส: ขนาดปุ่มกดเพียงพอหรือไม่, ลำดับการกด Tab ของคีย์บอร์ดลื่นไหลหรือไม่
  - แสงและคอนทราสต์: การแสดงผลข้อความสถานะในสภาวะแสงจ้าหรือมุมมองด้านข้าง
- [ ] **8.5 AI's Creative Open-Ended Exploration (ระบุการทดสอบพิเศษเฉพาะฟีเจอร์)**:
  - `[ให้ AI เสนอและทำการทดสอบเคสสร้างสรรค์ 1-2 เคสที่ออกแบบขึ้นมาเฉพาะสำหรับฟีเจอร์ที่เพิ่งพัฒนาหรือแก้ไข]`

*บันทึกผลการตรวจสอบมิติที่ 8*:  
`[ระบุสถานการณ์จำลองที่ AI ออกแบบขึ้น และผลการทดสอบที่ได้รับ]`

---

## 🌟 โปรโตคอลการยกระดับเข้าสู่เช็คลิสต์ถาวร (Checklist Evolution Protocol)

เมื่อ AI Agent หรือ QA ดำเนินการทดสอบใน **มิติที่ 8** แล้วพบกรณีทดสอบที่มีประโยชน์สูง (High-Value Test Case) หรือค้นพบบั๊กที่ควรเฝ้าระวังไม่ให้เกิดซ้ำในอนาคต:

1. **บันทึกลงรายงาน**: ระบุเคสดังกล่าวลงในหัวข้อ *"ข้อค้นพบจากการทดสอบเชิงสร้างสรรค์และการยกระดับเข้าเช็คลิสต์"* ในแบบฟอร์ม [QA_REPORT_TEMPLATE.md](file:///.agents/qa/QA_REPORT_TEMPLATE.md)
2. **อัปเดตไฟล์เช็คลิสต์ทันที**: 
   - ทำการแก้ไขไฟล์ `QA_CHECKLIST_TEMPLATE.md` นี้ โดยนำหัวข้อทดสอบใหม่ไปบรรจุไว้ในมิติที่เกี่ยวข้อง (มิติที่ 1-7) หรือเพิ่มเป็นข้อย่อยถาวร
   - ใส่สัญลักษณ์กำกับ `[Promoted from Creative QA: YYYY-MM-DD]` เพื่อเป็นเกียรติประวัติและหลักฐานการเรียนรู้ของระบบ
3. **ส่งต่อความจำ**: เมื่อบรรจุลงในเช็คลิสต์แล้ว AI Agent รุ่นถัดไปทุกตัวที่เข้ามาใน MASAPP จะต้องตรวจสอบเคสนี้เป็นประจำเสมอโดยอัตโนมัติ!

