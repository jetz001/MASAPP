# MASAPP

MASAPP (Maintenance & Asset System Application) เป็นแอป Flutter สำหรับ Windows ที่ใช้ SQLite แบบ offline-first เพื่อบริหารงานซ่อมบำรุง ทะเบียนเครื่องจักร อะไหล่ เครื่องมือ และเอกสารประกอบในโรงงาน

## ภาพรวมระบบ

- Frontend: Flutter Desktop
- Database: SQLite ผ่าน `sqflite_common_ffi`
- State management: Riverpod
- Routing: GoRouter
- AI assistant: multi-provider + DB-first exploration + external search แบบติดป้ายข้อมูลภายนอก
- File assets: ใช้ `file_assets` เป็น metadata กลาง และเก็บไฟล์จริงใน managed storage ข้างฐานข้อมูล

## ความสามารถหลัก

- จัดการทะเบียนเครื่องจักรและกระบวนการรับมอบเครื่อง
- เปิด/แนบรูปและ PDF ใน 4 โมดูลหลัก: เครื่องจักร, งานซ่อม, อะไหล่, เครื่องมือ
- แสดงผล AI chat ได้ทั้งข้อความ, code block, table, image, PDF card และ `timeline`
- รองรับ AI หลายเจ้า เช่น Gemini, OpenAI, Claude, DeepSeek, Grok, Mistral และ Ollama
- รองรับ external search และ image search โดยยึดหลัก DB-first

## เริ่มต้นใช้งาน

### Prerequisites

- Flutter SDK 3.x ขึ้นไป
- Visual Studio พร้อม Windows Desktop workload
- Inno Setup 6 เมื่อต้องการ build installer

### Run แอป

```bash
flutter pub get
flutter run -d windows
```

### ตั้งค่าฐานข้อมูล

1. เปิดหน้าล็อกอิน
2. กด `ตั้งค่าฐานข้อมูล`
3. เลือกไฟล์ฐานข้อมูล SQLite หรือสร้างใหม่
4. หากใช้ network share ให้ใช้ path ที่เข้าถึงได้จริง เช่น `\\server\share\masapp.db`

## Seed Database

- ไฟล์ seed สำหรับ SQLite อยู่ที่ `db/seed_sqlite.sql`
- ไฟล์ seed สำหรับ schema เดิมอีกชุดอยู่ที่ `db/seed.sql`
- `seedDB` ปัจจุบันตั้งค่าให้ fresh database ใช้ managed storage ตั้งแต่แรก
- ค่า `file_assets_legacy_storage_migrated_v1 = true` ถูก seed มาให้สำหรับฐานข้อมูลใหม่ เพื่อบอกว่าฐานใหม่ไม่ต้อง migrate path เก่า

ค่าเริ่มต้นที่เกี่ยวกับไฟล์แนบ:

- `assets.storage_mode = managed_storage`
- `assets.storage_root_strategy = db_relative_storage`

สรุปคือ fresh install หรือฐานข้อมูลที่สร้างใหม่จาก seed จะไม่ย้อนกลับไปใช้ path ลอยแบบ legacy flow เดิม เพราะฝั่งอัปโหลดใหม่ทุกจุดวิ่งผ่าน `AttachmentStorageService`

## Managed Storage และ Migration

- ไฟล์แนบใหม่จะถูก copy เข้า storage ที่ระบบจัดการเองข้างฐานข้อมูล
- metadata จะถูกเก็บในตาราง `file_assets`
- ระบบรองรับ preview/thumbnail สำหรับ image และ PDF
- ฐานข้อมูลเก่าที่มี path เดิมจะถูก migrate อัตโนมัติใน `DbInitializer`
- หลัง migrate สำเร็จ ระบบจะ rewrite path อ้างอิงในตารางเดิมให้ชี้มาที่ managed storage

โมดูลที่อยู่ใน flow นี้:

- `machine_handover`
- `work_order`
- `spare_part`
- `tool`

## Default Credentials

สำหรับ fresh install:

- Username: `admin`
- Password: `Admin@1234`
- PIN: `123456`

ควรเปลี่ยนรหัสผ่านทันทีหลังเข้าใช้งานครั้งแรก

## Build Installer

ตัว installer ใช้ไฟล์ `masapp_installer.iss` และตอนนี้รองรับการรับเวอร์ชันจากภายนอกแทนการ hardcode ไว้ในไฟล์อย่างเดียว

วิธีที่แนะนำ:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1
```

สิ่งที่ script ทำ:

- อ่านเวอร์ชันจาก `pubspec.yaml`
- ใช้เลขเวอร์ชันก่อน `+build` เป็นเวอร์ชัน installer
- build Windows release
- ส่งค่า version/build/output เข้า `masapp_installer.iss`

ถ้าต้องการเช็กก่อนโดยยังไม่ build installer:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1 -DryRun -SkipFlutterBuild
```

ดังนั้น flow ที่ควรใช้ต่อจากนี้คือ:

1. อัปเดตเวอร์ชันใน `pubspec.yaml`
2. push code เวอร์ชันนั้น
3. รัน `scripts/build_installer.ps1`
4. ได้ installer ที่ใช้เวอร์ชันเดียวกับแอป

ไฟล์ output ปกติจะอยู่ในโฟลเดอร์ `Output\`

## โครงสร้างโปรเจกต์

```text
lib/
├── core/
│   ├── ai/
│   ├── database/
│   ├── files/
│   └── storage/
├── features/
│   ├── ai_chat/
│   ├── auth/
│   ├── machine_intake/
│   ├── spare_parts/
│   ├── tools_equipment/
│   └── work_orders/
└── main.dart
```

## หมายเหตุ

- ระบบ AI ใช้หลัก DB-first ก่อนค้นหาภายนอกเสมอ
- ข้อมูลจากภายนอกต้องถูกติดป้ายว่าเป็นข้อมูลภายนอก
- ฐานข้อมูลของ AI เป็น read-only exploration สำหรับตารางที่ปลอดภัย

## License

Internal use only.
