# MASAPP - Modern Maintenance & Asset Management System

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Riverpod](https://img.shields.io/badge/State--Management-Riverpod-blue?style=for-the-badge)](https://riverpod.dev)
[![SQLite](https://img.shields.io/badge/Database-SQLite-003B57?style=for-the-badge&logo=sqlite&logoColor=white)](https://www.sqlite.org/)

**MASAPP** (Maintenance & Asset System Application) เป็นแพลตฟอร์มสำหรับบริหารจัดการงานซ่อมบำรุงและทะเบียนเครื่องจักรที่ทันสมัย ออกแบบมาเพื่อเพิ่มประสิทธิภาพในการติดตามสถานะเครื่องจักรในโรงงาน (Factory Floor Plan) แบบ Real-time และการจัดการข้อมูลเชิงเทคนิคที่ครบวงจร

---

## ✨ Key Features

### 🏢 Interactive Factory Layout
*   **Visual Floor Plan**: แสดงแผนผังโรงงานแบบโต้ตอบได้ รองรับการซูมและแพนภาพ
*   **Precision Alignment**: ระบบจัดตำแหน่งผังพื้น (Ruler Tool) ที่มีความแม่นยำสูง พร้อมตารางกริด (Grid Lines) ขนาด 5x5m เพื่อการวัดระยะที่ถูกต้อง
*   **Machine Tracking**: ติดตามตำแหน่งและสถานะของเครื่องจักรด้วยรหัสสี (Green: Normal, Red: Breakdown, Yellow: Maintenance)
*   **AI Floor Plan Scanning**: ระบบอัจฉริยะช่วยสแกนและตรวจจับพื้นที่โซนและตำแหน่งเครื่องจักรจากไฟล์ผังพื้น

### 📋 Machine Registry & Intake
*   **Comprehensive Data**: จัดเก็บข้อมูลเครื่องจักรอย่างละเอียด (Brand, Model, Serial No, Manuals)
*   **6-Stage Intake Process**: ระบบการนำเข้าเครื่องจักรใหม่ที่เป็นลำดับขั้นตอน ตั้งแต่ตรวจสอบเอกสารไปจนถึงการอนุมัติใช้งาน
*   **Handover Conclusion**: ระบบตัดสินใจ Pass/Fail สำหรับการรับมอบเครื่องจักร

### 📊 Reporting & Documentation
*   **High-Resolution PDF Export**: สร้างป้ายกำกับเครื่องจักร (Machine Tags) และรายงานตำแหน่งในรูปแบบ PDF ที่มีความละเอียดสูง
*   **Dashboard & Analytics**: สรุปสถิติการซ่อมบำรุงและสถานะเครื่องจักรทั้งหมดในรูปแบบกราฟ (fl_chart)

---

## 🛠 Technology Stack

*   **Frontend**: [Flutter](https://flutter.dev) (Desktop Optimized)
*   **State Management**: [Riverpod](https://riverpod.dev) (Robust & Testable)
*   **Database**: [SQLite (FFI)](https://pub.dev/packages/sqflite_common_ffi) สำหรับการจัดเก็บข้อมูลแบบ Offline-first บน Desktop
*   **Navigation**: [GoRouter](https://pub.dev/packages/go_router)
*   **UI Components**: 
    *   [Syncfusion DataGrid](https://www.syncfusion.com/flutter-widgets/flutter-datagrid) สำหรับจัดการข้อมูลตารางขนาดใหญ่
    *   [HugeIcons](https://hugeicons.com/) สำหรับชุดไอคอนระดับพรีเมียม
    *   [Form Builder](https://pub.dev/packages/flutter_form_builder) สำหรับการจัดการฟอร์มที่ซับซ้อน

---

## 🚀 Getting Started

### Prerequisites
*   Flutter SDK (3.x หรือสูงกว่า)
*   Visual Studio (สำหรับ Windows Desktop Development)

### Installation
1.  Clone the repository:
    ```bash
    git clone https://github.com/your-repo/masapp.git
    ```
2.  Install dependencies:
    ```bash
    flutter pub get
    ```
3.  Run the application:
    ```bash
    flutter run -d windows
    ```

---

## 📁 Project Structure

```text
lib/
├── core/               # Shared logic, theme, and database helpers
├── features/           # Feature-based modules
│   ├── auth/           # Authentication & User Management
│   ├── dashboard/      # Analytics & Overview
│   ├── factory_layout/ # Interactive Map & PDF Services
│   ├── machine_intake/ # Step-by-step Machine Registry
│   └── ...
└── main.dart           # Application Entry Point
```

---

## 📝 License
This project is for internal use within the maintenance department. All rights reserved.

---
*Developed with ❤️ by Antigravity (Advanced Agentic Coding)*
