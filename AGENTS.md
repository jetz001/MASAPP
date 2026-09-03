# MASAPP - Agent Memory & Development Guardrails

> **Target Platform**: Windows Desktop (Flutter 3.x)  
> **Database**: SQLite via `sqflite_common_ffi` (Offline-First)  
> **State Management**: Riverpod (`flutter_riverpod`)  
> **Routing**: GoRouter  
> **Storage Strategy**: Managed Storage (`file_assets` table + db-relative folder)

---

## 1. Core Architecture & Mental Model

1. **Offline-First & Local SQLite**:
   - The primary source of truth is SQLite.
   - All schema definitions reside in `lib/core/database/db_initializer.dart` and `db/seed_sqlite.sql`.
   - **Schema Migrations must be idempotent**: When adding new tables or columns, always check `DbInitializer.dart` migration logic. Use `IF NOT EXISTS` or check column existence before altering tables.

2. **Managed Storage Rules (`file_assets`)**:
   - **CRITICAL**: NEVER store hardcoded absolute Windows paths (e.g. `C:\Users\...` or `D:\DEV\...`) in SQLite data tables!
   - All attachment files (images, PDFs, documents) MUST go through `AttachmentStorageService`.
   - The storage strategy is `db_relative_storage`: attachments live in an `assets/` directory adjacent to the active database file.
   - Metadata is indexed in the `file_assets` table.

3. **Presentation & Export Modules**:
   - **Slide Presentation Studio**: Generates A4 Landscape PDFs (`PdfPageFormat.a4.landscape`). When modifying slide rendering, preserve Thai font loading (`THSarabunNew` / `GoogleFonts.sarabun`) and clean page breaks.
   - **Line Balancing Studio**: Interactive canvas for production balancing (Takt time, bottleneck calculation). Keep state pure in Riverpod without lingering side-effects.
   - **Action Plan Registry**: Tracks 8D reports, sub-step checklists, Before/Target/Actual metrics, and syncs summaries into `knowledge_vectors`.

4. **AI Assistant Integration**:
   - Multi-provider support (Gemini, OpenAI, Claude, DeepSeek, Ollama, etc.).
   - Strategy: **DB-first exploration**. Query local database/vectors first before performing external searches.
   - Attach metadata labels when referencing external search vs. local database facts.

---

## 2. QA & Verification Guardrails for AI

Whenever making changes to this codebase or running QA testing, the AI assistant MUST strictly adhere to the following standards:

1. **Mandatory QA Audit (8 Dimensions)**:
   - Every verification must evaluate the dimensions defined in [QA_CHECKLIST_TEMPLATE.md](file:///.agents/qa/QA_CHECKLIST_TEMPLATE.md):
     1. Database & Schema Migrations
     2. Managed Storage & File Assets
     3. Core Business Workflows (WO, Machines, Spare Parts, Tools)
     4. Presentation & PDF Export (Landscape A4, Thai Fonts)
     5. Line Balancing Studio (Calculations & Pure Riverpod State)
     6. AI Assistant & Vector Exploration (DB-First)
     7. Windows Desktop Stability & UI/UX (Zero Crashes, Window Resizing)
     8. **Creative, Chaos & Exploratory Testing**: AI is encouraged to think outside the box—simulating race conditions, weird inputs, double-clicks, and operator factory scenarios.

2. **Continuous Learning & Checklist Evolution**:
   - Whenever an AI agent's creative exploration uncovers a subtle bug, race condition, or high-value test case:
     - The agent **MUST immediately promote and append** this new check into [QA_CHECKLIST_TEMPLATE.md](file:///.agents/qa/QA_CHECKLIST_TEMPLATE.md).
     - Record the promotion in [QA_REPORT_TEMPLATE.md](file:///.agents/qa/QA_REPORT_TEMPLATE.md) under the Creative Findings section.
     - This guarantees the project continuously learns and immunizes against regressions across AI generations.

3. **Standard QA Report Output**:
   - Whenever asked to perform QA or before completing feature milestones, the AI agent must compile and format findings using [QA_REPORT_TEMPLATE.md](file:///.agents/qa/QA_REPORT_TEMPLATE.md).
   - **Zero Critical/High Defects**: Tasks must NEVER be marked as complete or signed off for production if any Critical or High severity defects remain open.

3. **Run QA Before Marking Tasks Complete**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\run_qa.ps1
   ```
   Or run individual checks:
   ```bash
   flutter test
   ```

4. **Never Break Existing Tests**:
   - Ensure `test/db_schema_seed_test.dart`, `test/widget_test.dart`, and all unit tests remain 100% passing.

5. **No Unhandled Nulls / Desktop Crashes**:
   - Windows desktop apps run in an unconstrained environment. Always handle file permissions, missing files, dialog cancellations, and window resizing safely.

6. **Encoding & Thai Language**:
   - Always save source files and assets with UTF-8 encoding. Thai font metrics require fallback font handling in PDF services.

---

## 3. Quick Reference Commands

| Task | Command |
| :--- | :--- |
| **Run QA Suite** | `powershell -ExecutionPolicy Bypass -File .\scripts\run_qa.ps1` |
| **Run Tests** | `flutter test` |
| **Analyze Code** | `flutter analyze` |
| **Run App (Windows)** | `flutter run -d windows` |
| **Build Installer** | `powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1` |
