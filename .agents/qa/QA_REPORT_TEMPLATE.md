# MASAPP - แบบฟอร์มรายงานผลการทดสอบคุณภาพมาตรฐาน (Standard QA Test Report)

> **คำแนะนำสำหรับ AI Agent**:  
> ใช้แบบฟอร์มนี้เป็นมาตรฐานในการจัดทำรายงานผลการทดสอบทุกครั้งที่ได้รับคำสั่งให้ทดสอบ, ตรวจสอบคุณภาพ หรือก่อนส่งมอบงาน โดยกรอกข้อมูลให้ครบถ้วนทุกหัวข้อ

---

## 1. ข้อมูลการทดสอบ (Audit Metadata)

- **รหัสการทดสอบ (Audit ID)**: `QA-[YYYYMMDD]-[RUN_NO]`
- **วันที่และเวลาที่ทดสอบ**: `[YYYY-MM-DD HH:mm:ss]`
- **ระบบและเวอร์ชัน**: MASAPP v`[Version from pubspec.yaml]` (Windows Desktop x64)
- **สภาพแวดล้อม (Environment)**: Windows Desktop / Local SQLite FFI / Offline Mode
- **ผู้ดำเนินการทดสอบ**: `[Agent Name / Engineer Name]`
- **สถานะภาพรวม (Overall Verdict)**: **`[PASSED / FAILED / BLOCKED]`**

---

## 2. ตัวชี้วัดการรันชุดทดสอบอัตโนมัติ (Automated Test Execution Metrics)

| ตัวชี้วัด (Metric) | ค่าที่ได้ (Actual) | เกณฑ์เป้าหมาย (Benchmark) | สถานะ (Status) |
| :--- | :---: | :---: | :---: |
| **คำสั่งที่ใช้รัน (Test Command)** | `.\scripts\run_qa.ps1` | สำเร็จครบวงจร | PASS / FAIL |
| **Static Analysis Errors** | `[X]` errors | 0 errors | PASS / FAIL |
| **Static Analysis Warnings/Infos** | `[X]` warnings | ไม่มี Warning วิกฤต | PASS / FAIL |
| **จำนวนชุดทดสอบที่ผ่าน (Pass Rate)** | `[X]/[Total]` (`[X]%`) | 100% | PASS / FAIL |
| **จำนวนการทดสอบที่ล้มเหลว (Failed Tests)** | `[0]` | 0 | PASS / FAIL |
| **ระยะเวลาในการทดสอบ (Elapsed Time)** | `[X]m [X]s` | < 60 วินาที | PASS / FAIL |
| **Exit Code** | `[0]` | 0 | PASS / FAIL |

---

## 3. สรุปผลการตรวจสอบครบ 8 มิติ (8-Dimension Test Summary)

| มิติการทดสอบ (Dimension) | รายละเอียดที่ทดสอบ | ผลลัพธ์ (Verdict) | บันทึกหลักฐาน (Evidence / Notes) |
| :--- | :--- | :---: | :--- |
| **1. ฐานข้อมูลและการย้ายข้อมูล**<br>*(Database & Migrations)* | Fresh setup, Idempotency, Schema integrity, Seed data | **PASS / FAIL** | `test/db_schema_seed_test.dart` ผ่าน |
| **2. การจัดการไฟล์แนบ**<br>*(Managed Storage)* | Path สัมพัทธ์, ตาราง `file_assets`, ไม่มี Hardcoded absolute path | **PASS / FAIL** | `test/unit/storage_and_assets_test.dart` ผ่าน |
| **3. กระบวนการทางธุรกิจ**<br>*(Core Workflows)* | วงจรใบสั่งซ่อม (WO), การรับมอบเครื่องจักร, อะไหล่, เครื่องมือ | **PASS / FAIL** | `test/unit/work_order_models_test.dart` ผ่าน |
| **4. การออกเอกสารและรายงาน**<br>*(Presentation & PDF)* | Slide A4 แนวนอน, Sarabun Thai Font, Work Permit, 8D Report | **PASS / FAIL** | ทดสอบการ Render PDF สำเร็จ |
| **5. หน้าจอ Canvas & วิศวกรรม**<br>*(Line Balancing)* | Takt Time, Bottleneck, สถานะ Pure State ใน Riverpod | **PASS / FAIL** | คำนวณถูกต้องตามทฤษฎี |
| **6. ระบบผู้ช่วย AI และ Vector**<br>*(AI & Vector Search)* | DB-First exploration, Knowledge vector retrieval, Multi-provider | **PASS / FAIL** | Query Local Vector ได้สมบูรณ์ |
| **7. ความเสถียรบน Windows Desktop**<br>*(Desktop Robustness)* | Window resizing, Dialog null safety, UTF-8, ไม่พบ Crash | **PASS / FAIL** | `test/widget_test.dart` ผ่าน |
| **8. การทดสอบเชิงสร้างสรรค์/Chaos**<br>*(Creative & Exploratory)* | Boundary inputs, Concurrency / Double-clicks, Fault injection | **PASS / FAIL** | ระบุผลการทดสอบเคสพิเศษ |

---

## 4. ข้อค้นพบจากการทดสอบเชิงสร้างสรรค์และการยกระดับเข้าเช็คลิสต์ (Creative Findings & Checklist Promotions)

> บันทึกกรณีทดสอบสร้างสรรค์ที่ AI หรือ QA คิดค้นขึ้น หากเคสใดมีประโยชน์สูง ให้ดำเนินการเพิ่มเข้าไปใน `QA_CHECKLIST_TEMPLATE.md` ทันที

| หัวข้อทดสอบสร้างสรรค์ (Creative Test Scenario) | ผลกระทบและความเสี่ยงที่พบ (Impact / Risk) | ข้อเสนอแนะการยกระดับ (Promotion Recommendation) | สถานะการบรรจุเข้า Checklist |
| :--- | :--- | :--- | :---: |
| *ตัวอย่าง: ทดสอบกรอกทศนิยม 10 หลักใน Takt Time* | *ตัวเลขล้นการ์ดแสดงผลบน Canvas* | *เพิ่มข้อตรวจเช็ค Format ตัวเลขในมิติที่ 5* | `[PROMOTED: YYYY-MM-DD]` / `[N/A]` |
| `[ระบุเคสทดสอบสร้างสรรค์]` | `[ระบุสิ่งที่พบ]` | `[ระบุข้อเสนอแนะ]` | `[Pending / Promoted]` |

---

## 5. บันทึกข้อบกพร่องและการแก้ไข (Defect & Remediation Tracker)

> หากพบข้อบกพร่อง ให้บันทึกตามตารางนี้ หากไม่มีข้อบกพร่องให้ระบุ `"ไม่พบข้อบกพร่อง (Zero Defects)"`

| รหัสข้อบกพร่อง (Defect ID) | รายละเอียดข้อบกพร่อง (Description) | ระดับความรุนแรง (Severity) | สาเหตุที่แท้จริง (Root Cause) | แนวทางแก้ไข (Remediation) | สถานะ (Status) |
| :---: | :--- | :---: | :--- | :--- | :---: |
| **DEF-01** | `[ระบุข้อผิดพลาดที่พบ]` | `Critical / High / Medium / Low` | `[สาเหตุ]` | `[วิธีแก้]` | `Resolved / Open` |

---

## 6. การประเมินความพร้อมสำหรับการ Release (Go / No-Go Verdict)

- [ ] **เกณฑ์ 1**: การทดสอบอัตโนมัติทั้งหมด (`run_qa.ps1`) ผ่าน 100% (Zero Failed)
- [ ] **เกณฑ์ 2**: ไม่มีข้อบกพร่องระดับ **Critical** หรือ **High** หลงเหลืออยู่ในระบบ
- [ ] **เกณฑ์ 3**: ไม่มีการฝัง Hardcoded Absolute Windows Path ในฐานข้อมูล SQLite
- [ ] **เกณฑ์ 4**: การ Export เอกสาร PDF สำคัญ (สไลด์แนวนอน, ใบแจ้งซ่อม) แสดงภาษาไทยถูกต้อง
- [ ] **เกณฑ์ 5**: ตัวติดตั้ง Windows (`build_installer.ps1`) สามารถ Build ผ่านได้สมบูรณ์

### สรุปคำตัดสิน (Final Decision):
👉 **`[ GO FOR PRODUCTION / NO-GO (REQUIRES FIXES) ]`**

**ผู้ลงนามอนุมัติผลการทดสอบ**:  
ลงชื่อ: `....................................................` (`[ชื่อ Agent หรือ QA Lead]`)  
วันที่: `[YYYY-MM-DD]`
