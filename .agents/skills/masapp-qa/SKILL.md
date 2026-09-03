---
name: masapp-qa
description: QA automation, testing procedures, database integrity verification, and smoke tests for MASAPP Flutter Windows desktop application.
---

# MASAPP QA & Verification Skill

Use this skill when tasked with testing, verifying changes, running regression checks, or validating database integrity in MASAPP.

## 1. Quick QA Execution

To run the complete automated QA pipeline:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_qa.ps1
```

Or run targeted test commands:
```bash
# Run all unit and widget tests
flutter test

# Run only database schema and seed integrity tests
flutter test test/db_schema_seed_test.dart

# Run storage and asset tests
flutter test test/unit/storage_and_assets_test.dart
```

---

## 2. Core QA Checklist for AI Agents

Before marking any task as complete, verify:

1. **Database Schema Integrity**:
   - Every new table or column must be reflected in `lib/core/database/db_initializer.dart`.
   - Run `flutter test test/db_schema_seed_test.dart` to guarantee that fresh installations and re-initializations work cleanly without crashing.

2. **Attachment & Managed Storage Rules**:
   - Attachments must never use hardcoded absolute paths (`C:\...`).
   - Run `test/unit/storage_and_assets_test.dart` to verify relative paths and storage modes.

3. **Flutter Static Analysis**:
   - Run `flutter analyze` to ensure there are no compilation errors or fatal warnings introduced.

4. **PDF and Export Validation**:
   - When modifying PDF services (`work_order_pdf_service.dart`, `slide_presentation_pdf_service.dart`), ensure that page dimensions (`PdfPageFormat.a4` vs `PdfPageFormat.a4.landscape`) and Thai font fallbacks are intact.

5. **Windows Desktop Error Handling**:
   - Ensure file pickers and dialogs handle user cancellations (`null` returns) gracefully without throwing uncaught exceptions.

---

## 3. Mandatory 8-Dimension QA Audit Workflow

All QA audits must evaluate the dimensions defined in [.agents/qa/QA_CHECKLIST_TEMPLATE.md](file:///.agents/qa/QA_CHECKLIST_TEMPLATE.md):
1. **Database & Migrations**: Idempotent schema, FK integrity, seed alignment.
2. **Managed Storage**: No absolute paths, relative storage layout, derivative generation.
3. **Core Business Workflows**: Work order status state machine, handover, parts, tools.
4. **Presentation & Reporting**: A4 landscape slides, Thai font rendering, print preview.
5. **Line Balancing Studio**: Takt time, bottleneck calculation, pure Riverpod state.
6. **AI Assistant & Vector System**: DB-first retrieval, knowledge vector sync.
7. **Windows Desktop & UI/UX**: Resizing robustness, dialog null safety, UTF-8.
8. **Creative, Chaos & Exploratory Testing**: AI-driven creative scenarios, boundary inputs, button mashing / concurrency simulation, fault injection, and factory floor ergonomics.

---

## 4. Creative Findings & Checklist Evolution Protocol

When conducting tests under **Dimension 8**:
1. **Explore Creatively**: Formulate 1-2 creative hypotheses or chaos tests tailored to the feature being modified.
2. **Promote Valuable Cases**: If a creative test discovers a potential failure mode or proves to be a critical invariant, the agent **MUST** update [.agents/qa/QA_CHECKLIST_TEMPLATE.md](file:///.agents/qa/QA_CHECKLIST_TEMPLATE.md) to permanently include it.
3. **Document in Report**: Fill out the *"Creative Findings & Checklist Promotions"* table in [.agents/qa/QA_REPORT_TEMPLATE.md](file:///.agents/qa/QA_REPORT_TEMPLATE.md).

---

## 5. Standard QA Reporting Procedure

Every time QA testing is conducted:
1. Run `powershell -ExecutionPolicy Bypass -File .\scripts\run_qa.ps1`
2. Follow [.agents/qa/QA_REPORT_TEMPLATE.md](file:///.agents/qa/QA_REPORT_TEMPLATE.md) to generate the formal QA report.
3. Verify that **Zero Critical or High severity defects** remain open before certifying the task as `GO FOR PRODUCTION`.
