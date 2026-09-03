---
name: masapp-dev
description: Development guide, architecture conventions, database migration steps, and release build workflows for MASAPP.
---

# MASAPP Developer & Architecture Guide

Use this skill when developing new features, modifying SQLite schemas, working on PDF exports, or packaging Windows releases.

## 1. Project Architecture

- **UI Framework**: Flutter Desktop for Windows
- **State Management**: Riverpod (`ConsumerWidget`, `ref.watch`, `ref.read`)
- **Routing**: GoRouter with dedicated route constants in `lib/core/routing/`
- **Database**: SQLite with `sqflite_common_ffi`
- **Managed Storage**: `AttachmentStorageService` handles relative file saving and metadata registration in `file_assets`.

---

## 2. Database & Schema Changes

When modifying the database schema:

1. **Update `lib/core/database/db_initializer.dart`**:
   - Add table creation in `_createTables()`.
   - Add idempotent migration steps in `_applyMigrations()` so existing databases upgrade smoothly without data loss.
2. **Update `db/seed_sqlite.sql`**:
   - Keep seed SQL aligned with the current schema for fresh database creation.
3. **Verify with test**:
   ```bash
   flutter test test/db_schema_seed_test.dart
   ```

---

## 3. PDF & Presentation Export Patterns

- **Slide Presentation Studio**:
  - Export orientation: `PdfPageFormat.a4.landscape`
  - Uses `pdf` and `printing` packages.
  - Supports 1-click preview and opening via system default viewer.
- **Thai Font Handling**:
  - Thai text in PDF requires Sarabun / THSarabunNew font bytes loaded via `rootBundle` or Google Fonts.

---

## 4. Packaging & Windows Installer

To build an installer for production deployment:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_installer.ps1
```
The script reads the version from `pubspec.yaml`, compiles the release binary (`flutter build windows --release`), and uses Inno Setup (`masapp_installer.iss`) to produce the setup executable in `Output/`.
