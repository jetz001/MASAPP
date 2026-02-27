import os
from datetime import datetime
from PyQt6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QLabel, QTableWidget, QTableWidgetItem,
    QHeaderView, QDialog, QFormLayout, QComboBox, QLineEdit, QTextEdit, QMessageBox,
    QScrollArea, QFrame, QTabWidget, QSpinBox, QDoubleSpinBox, QFileDialog
)
from PyQt6.QtCore import Qt
from models import WorkOrder, Machine, WorkOrderLabor, WorkOrderVendor, SparePart, WorkOrderPart, User
from services import WorkOrderService, MachineService

class RepairManagementPage(QWidget):
    def __init__(self, current_user=None):
        super().__init__()
        self.current_user = current_user
        self.svc = WorkOrderService()
        self.machine_svc = MachineService()
        if self.current_user:
            self.svc.set_current_user(self.current_user)
            self.machine_svc.set_current_user(self.current_user)
            
        from views import ThemeManager, make_label
        self.ThemeManager = ThemeManager
        self.make_label = make_label
            
        self._build_ui()
        self.refresh()

    def refresh(self):
        # Clear existing
        for c_lay in [self.lay_todo, self.lay_doing, self.lay_done, self.lay_archive]:
            while c_lay.count():
                item = c_lay.takeAt(0)
                if item.widget():
                    item.widget().deleteLater()
                    
        wos = self.svc.get_all_work_orders()
        search_text = self.search_in.text().lower()
        
        for wo in wos:
            # Filter
            code = f"wo-{wo.id:04d}".lower()
            fc = (wo.failure_code or "").lower()
            mn = (wo.machine.name if wo.machine else "").lower()
            desc = (wo.description or "").lower()
            if search_text not in code and search_text not in fc and search_text not in mn and search_text not in desc:
                continue
                
            card = WorkOrderCard(wo, self)
            if wo.status in ['New', 'Approved']:
                self.lay_todo.addWidget(card)
            elif wo.status in ['In Progress', 'Hold']:
                self.lay_doing.addWidget(card)
            elif wo.status in ['Done']:
                self.lay_done.addWidget(card)
            elif wo.status in ['Closed']:
                self.lay_archive.addWidget(card)

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        
        # Header
        header = QHBoxLayout()
        header.addWidget(self.make_label("🛠️ กระดานใบแจ้งซ่อม (Kanban Board)", 18, bold=True))
        header.addStretch()
        
        add_btn = QPushButton("➕ สร้างใบแจ้งงานใหม่")
        add_btn.setObjectName("btn_primary")
        add_btn.clicked.connect(self._create_wo)
        header.addWidget(add_btn)
        
        root.addLayout(header)
        
        # Filters
        filters = QHBoxLayout()
        self.search_in = QLineEdit()
        self.search_in.setPlaceholderText("ค้นหาด้วย ID, เครื่องจักร, รายละเอียด...")
        self.search_in.textChanged.connect(self.refresh)
        filters.addWidget(self.search_in)
        
        dl_btn = QPushButton("ดาวน์โหลดข้อมูล")
        dl_btn.clicked.connect(self._download_history)
        filters.addWidget(dl_btn)
        root.addLayout(filters)
        
        # Kanban Board
        board_lay = QHBoxLayout()
        
        self.col_todo, self.lay_todo = self._create_kanban_column("TO DO (รอดำเนินการ)", "#ffebee", "#c62828")
        self.col_doing, self.lay_doing = self._create_kanban_column("DOING (กำลังดำเนินการ)", "#e3f2fd", "#1565c0")
        self.col_done, self.lay_done = self._create_kanban_column("DONE (รอตรวจรับ)", "#e8f5e9", "#2e7d32")
        self.col_archive, self.lay_archive = self._create_kanban_column("ARCHIVE (ปิดงานแล้ว)", "#f5f5f5", "#424242")
        
        board_lay.addWidget(self.col_todo)
        board_lay.addWidget(self.col_doing)
        board_lay.addWidget(self.col_done)
        board_lay.addWidget(self.col_archive)
        
        root.addLayout(board_lay)
        
    def _create_kanban_column(self, title, bg_color, header_color):
        container = QWidget()
        lay = QVBoxLayout(container)
        lay.setContentsMargins(0, 0, 0, 0)
        
        header = QLabel(f"<b>{title}</b>")
        header.setStyleSheet(f"background-color: {bg_color}; color: {header_color}; padding: 10px; border-radius: 4px; font-size: 14px;")
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(header)
        
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet(f"QScrollArea {{ border: 1px solid #e0e0e0; background-color: #fafafa; border-radius: 4px; }} QScrollBar {{ width: 8px; }}")
        
        content = QWidget()
        content.setStyleSheet("background-color: transparent;")
        content_lay = QVBoxLayout(content)
        content_lay.setAlignment(Qt.AlignmentFlag.AlignTop)
        content_lay.setContentsMargins(6, 6, 6, 6)
        content_lay.setSpacing(8)
        
        scroll.setWidget(content)
        lay.addWidget(scroll)
        
        return container, content_lay
        
    def _download_history(self):
        QMessageBox.information(self, "Download", "เตรียมพร้อมสำหรับการเพิ่มการดาวน์โหลด Excel/PDF ในอนาคต")
            
    def _create_wo(self):
        dlg = CreateWorkOrderDialog(self)
        if dlg.exec():
            data = dlg.get_data()
            try:
                self.svc.create_work_order(data)
                self.refresh()
                QMessageBox.information(self, "สำเร็จ", "สร้างใบแจ้งงานเรียบร้อยแล้ว")
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", str(e))
                
    def _delete_wo(self, wo_id):
        if getattr(self.current_user, 'role', '') != 'Admin':
            QMessageBox.warning(self, "สิทธิ์ไม่เพียงพอ", "คุณไม่มีสิทธิ์ลบข้อมูลใบแจ้งงานนี้")
            return
            
        confirm = QMessageBox.question(self, "ยืนยันการลบ", f"คุณต้องการลบใบแจ้งงาน WO-{wo_id:04d} ใช่หรือไม่?\n⚠️ การกระทำนี้ไม่สามารถกู้คืนได้", QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if confirm == QMessageBox.StandardButton.Yes:
            try:
                self.svc.delete_work_order(wo_id)
                self.refresh()
                QMessageBox.information(self, "ลบสำเร็จ", f"ข้อมูล WO-{wo_id:04d} ถูกลบออกจากระบบแล้ว")
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", str(e))
                
    def _print_wo(self, wo_id):
        from services import ReportingService
        import os
        try:
            rsvc = ReportingService()
            path = rsvc.generate_pm_work_order(wo_id) # Using existing function now adapted generically
            if hasattr(os, 'startfile'):
                os.startfile(path)
            else:
                import subprocess
                subprocess.call(('xdg-open', path))
        except Exception as e:
            QMessageBox.critical(self, "ข้อผิดพลาด", str(e))
                
    def _manage_wo(self, wo):
        dlg = WorkOrderExecutionDialog(wo.id, self)
        if dlg.exec():
            self.refresh()
            
    def _edit_wo(self, wo):
        dlg = CreateWorkOrderDialog(self, wo=wo)
        if dlg.exec():
            data = dlg.get_data()
            try:
                self.svc.update_work_order(wo.id, data)
                self.refresh()
                QMessageBox.information(self, "สำเร็จ", f"อัปเดตใบแจ้งงาน WO-{wo.id:04d} เรียบร้อยแล้ว")
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", str(e))

class CreateWorkOrderDialog(QDialog):
    def __init__(self, parent=None, wo=None):
        super().__init__(parent)
        self.parent_page = parent
        self.wo = wo
        self.setWindowTitle("แก้ไขใบแจ้งงาน" if wo else "สร้างใบแจ้งงานใหม่")
        self.setFixedWidth(500)
        
        svc = MachineService()
        if parent and parent.current_user:
            svc.set_current_user(parent.current_user)
        self.machines = svc.get_all_machines()
        
        self._build_ui()
        
    def _build_ui(self):
        lay = QFormLayout(self)
        
        self.type_cb = QComboBox()
        self.type_cb.addItem("ซ่อมเครื่องจักร (Breakdown)", "Breakdown")
        self.type_cb.addItem("สร้างชิ้นงาน (Fabrication)", "Fabrication")
        self.type_cb.addItem("ดัดแปลง/ปรับปรุง (Modification)", "Modification")
        self.type_cb.addItem("งานทั่วไป (General)", "General")
        lay.addRow("ประเภทงาน:", self.type_cb)
        
        self.urgency_cb = QComboBox()
        self.urgency_cb.addItem("ปกติ (Normal)", "Normal")
        self.urgency_cb.addItem("ต่ำ (Low)", "Low")
        self.urgency_cb.addItem("สูง (High)", "High")
        self.urgency_cb.addItem("วิกฤต (Critical)", "Critical")
        lay.addRow("ความเร่งด่วน (SLA):", self.urgency_cb)
        
        self.machine_cb = QComboBox()
        self.machine_cb.addItem("-- ไม่ระบุเครื่องจักร (งานทั่วไป/Fabrication) --", None)
        for m in self.machines:
            self.machine_cb.addItem(f"{m.code} - {m.name}", m.id)
        lay.addRow("เครื่องจักร/พื้นที่:", self.machine_cb)
        
        self.origin_cb = QComboBox()
        self.origin_cb.addItem("แจ้งซ่อมทั่วไป (Manual)", "Manual")
        self.origin_cb.addItem("พบความผิดปกติจาก AM (AM_Defect)", "AM_Defect")
        self.origin_cb.addItem("พบปัญหาจาก PM (PM_Failed)", "PM_Failed")
        lay.addRow("ที่มาของงาน (Origin):", self.origin_cb)
        
        self.failure_code_in = QLineEdit()
        self.failure_code_in.setPlaceholderText("ระบุอาการเสีย...")
        lay.addRow("อาการเสีย:", self.failure_code_in)
        
        self.desc_in = QTextEdit()
        self.desc_in.setPlaceholderText("อธิบายปัญหา / รายละเอียดงาน...")
        self.desc_in.setFixedHeight(100)
        lay.addRow("รายละเอียด:", self.desc_in)
        
        # Pre-fill data if editing
        if self.wo:
            self.type_cb.setCurrentIndex(self.type_cb.findData(self.wo.wo_type))
            self.urgency_cb.setCurrentIndex(self.urgency_cb.findData(self.wo.priority))
            idx = self.machine_cb.findData(self.wo.machine_id)
            if idx >= 0: self.machine_cb.setCurrentIndex(idx)
            self.origin_cb.setCurrentIndex(self.origin_cb.findData(self.wo.origin))
            self.failure_code_in.setText(self.wo.failure_code)
            self.desc_in.setPlainText(self.wo.description)
        
        btns = QHBoxLayout()
        btns.addStretch()
        submit = QPushButton("บันทึกการแก้ไข" if self.wo else "สร้างใบแจ้งงาน")
        submit.setObjectName("btn_primary")
        submit.clicked.connect(self.accept)
        cancel = QPushButton("ยกเลิก")
        cancel.clicked.connect(self.reject)
        btns.addWidget(submit)
        btns.addWidget(cancel)
        
        lay.addRow(btns)
        
    def get_data(self):
        machine_id = self.machine_cb.currentData()
        return {
            "wo_type": self.type_cb.currentData(),
            "priority": self.urgency_cb.currentData(),
            "machine_id": machine_id if machine_id else None,
            "description": self.desc_in.toPlainText(),
            "origin": self.origin_cb.currentData(),
            "failure_code": self.failure_code_in.text().strip(),
            "status": "New"
        }

class WorkOrderExecutionDialog(QDialog):
    def __init__(self, wo_id, parent=None):
        super().__init__(parent)
        self.wo_id = wo_id
        self.parent_page = parent
        self.svc = WorkOrderService()
        if parent and parent.current_user:
            self.svc.set_current_user(parent.current_user)
            
        self.setWindowTitle(f"จัดการใบแจ้งงาน #{wo_id}")
        self.setMinimumSize(700, 500)
        self._load_wo()
        self._build_ui()
        
    def _load_wo(self):
        self.wo = self.svc.db.query(WorkOrder).filter(WorkOrder.id == self.wo_id).first()
        
    def _build_ui(self):
        main = QVBoxLayout(self)
        
        # Info Header
        info_lay = QHBoxLayout()
        info_text = f"<b>ประเภท:</b> {self.wo.wo_type} | <b>สถานะ:</b> {self.wo.status} | <b>SLA:</b> {self.wo.sla_deadline.strftime('%Y-%m-%d %H:%M') if self.wo.sla_deadline else 'N/A'}"
        info_lbl = QLabel(info_text)
        info_lay.addWidget(info_lbl)
        main.addLayout(info_lay)
        
        # Tabs
        self.tabs = QTabWidget()
        self.tabs.addTab(self._tab_details(), "รายละเอียด")
        self.tabs.addTab(self._tab_labor(), "ผู้ดำเนินงาน (Labor)")
        self.tabs.addTab(self._tab_vendor(), "ผู้รับเหมา (Vendor)")
        self.tabs.addTab(self._tab_parts(), "อะไหล่ (Parts)")
        if self.wo.wo_type == 'Breakdown':
            self.tabs.addTab(self._tab_rca(), "วิเคราะห์สาเหตุ (RCA)")
            
        main.addWidget(self.tabs)
        
        # Actions
        actions = QHBoxLayout()
        actions.addStretch()
        
        if self.wo.status == 'New' and self.wo.wo_type in ['Fabrication', 'Modification']:
            approve_btn = QPushButton("✔️ อนุมัติ (Approve)")
            approve_btn.setObjectName("btn_accent")
            approve_btn.clicked.connect(self._approve_wo)
            actions.addWidget(approve_btn)
            
        if self.wo.status in ['New', 'Approved', 'Hold']:
            start_btn = QPushButton("▶️ เริ่มงาน (In Progress)")
            start_btn.setObjectName("btn_primary")
            start_btn.clicked.connect(lambda: self._set_status("In Progress"))
            actions.addWidget(start_btn)
            
        if self.wo.status == 'In Progress':
            hold_btn = QPushButton("⏸️ พักงาน (Hold)")
            hold_btn.setObjectName("btn_secondary")
            hold_btn.clicked.connect(self._hold_wo)
            actions.addWidget(hold_btn)
            
            done_btn = QPushButton("✅ แจ้งซ่อมเสร็จ (Done)")
            done_btn.setObjectName("btn_accent")
            done_btn.clicked.connect(self._done_wo)
            actions.addWidget(done_btn)
            
        if self.wo.status == 'Done':
            accept_btn = QPushButton("📝 ตรวจรับงาน (Accept & Close)")
            accept_btn.setObjectName("btn_primary")
            accept_btn.clicked.connect(self._accept_wo)
            actions.addWidget(accept_btn)
            
        close_btn = QPushButton("ปิดหน้าต่าง")
        close_btn.clicked.connect(self.accept)
        actions.addWidget(close_btn)
        
        main.addLayout(actions)
        
    def _tab_details(self):
        page = QWidget()
        lay = QVBoxLayout(page)
        lay.addWidget(QLabel("<b>รายละเอียดปัญหา:</b>"))
        desc = QTextEdit(self.wo.description)
        desc.setReadOnly(True)
        lay.addWidget(desc)
        lay.addStretch()
        return page
        
    def _tab_labor(self):
        page = QWidget()
        lay = QVBoxLayout(page)
        
        self.labor_table = QTableWidget(0, 4)
        self.labor_table.setHorizontalHeaderLabels(["ช่างเทคนิค", "เวลา (นาที)", "ค่าแรง/ชม.", "รวม (บาท)"])
        self.labor_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        lay.addWidget(self.labor_table)
        
        add_btn = QPushButton("➕ เพิ่ม/บันทึกเวลา ช่างเทคนิค")
        add_btn.clicked.connect(self._add_labor)
        lay.addWidget(add_btn)
        
        self._populate_labor()
        return page
        
    def _populate_labor(self):
        labors = self.svc.db.query(WorkOrderLabor).filter(WorkOrderLabor.work_order_id == self.wo_id).all()
        self.labor_table.setRowCount(len(labors))
        for i, l in enumerate(labors):
            self.labor_table.setItem(i, 0, QTableWidgetItem(l.user.username if l.user else f"User ID {l.user_id}"))
            self.labor_table.setItem(i, 1, QTableWidgetItem(str(l.actual_minutes)))
            self.labor_table.setItem(i, 2, QTableWidgetItem(f"{l.hourly_rate:,.2f}"))
            total = (l.actual_minutes / 60.0) * l.hourly_rate
            self.labor_table.setItem(i, 3, QTableWidgetItem(f"{total:,.2f}"))
            
    def _add_labor(self):
        dlg = AddLaborDialog(self.wo_id, self)
        if dlg.exec():
            self._populate_labor()
        
    def _tab_vendor(self):
        page = QWidget()
        lay = QVBoxLayout(page)
        
        self.vendor_table = QTableWidget(0, 3)
        self.vendor_table.setHorizontalHeaderLabels(["ผู้รับเหมา", "ค่าบริการ (บาท)", "ไฟล์แนบ"])
        self.vendor_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        lay.addWidget(self.vendor_table)
        
        add_btn = QPushButton("➕ เพิ่มผู้รับเหมา/Outsource")
        add_btn.clicked.connect(self._add_vendor)
        lay.addWidget(add_btn)
        
        self._populate_vendor()
        return page
        
    def _populate_vendor(self):
        vendors = self.svc.db.query(WorkOrderVendor).filter(WorkOrderVendor.work_order_id == self.wo_id).all()
        self.vendor_table.setRowCount(len(vendors))
        for i, v in enumerate(vendors):
            self.vendor_table.setItem(i, 0, QTableWidgetItem(v.vendor_name))
            self.vendor_table.setItem(i, 1, QTableWidgetItem(f"{v.service_cost:,.2f}"))
            has_files = []
            if v.quote_file_path: has_files.append("Quote")
            if v.report_file_path: has_files.append("Report")
            self.vendor_table.setItem(i, 2, QTableWidgetItem(f"{', '.join(has_files) if has_files else 'ไม่มี'}"))

    def _add_vendor(self):
        dlg = AddVendorDialog(self.wo_id, self)
        if dlg.exec():
            self._populate_vendor()
        
    def _tab_parts(self):
        page = QWidget()
        lay = QVBoxLayout(page)
        
        hl = QHBoxLayout()
        hl.addWidget(QLabel("<b>รายการอะไหล่ที่เบิก:</b>"))
        hl.addStretch()
        
        if self.wo.machine_id:
            sug_btn = QPushButton("💡 แนะนำอะไหล่ (Smart Suggestion)")
            sug_btn.setObjectName("btn_accent")
            sug_btn.clicked.connect(self._show_suggestions)
            hl.addWidget(sug_btn)
            
        add_btn = QPushButton("➕ เบิกอะไหล่ใหม่")
        add_btn.clicked.connect(self._add_part)
        hl.addWidget(add_btn)
        lay.addLayout(hl)
        
        self.part_table = QTableWidget(0, 3)
        self.part_table.setHorizontalHeaderLabels(["รหัส/ชื่ออะไหล่", "จำนวนที่เบิก", "รวม (บาท)"])
        self.part_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        lay.addWidget(self.part_table)
        
        self._populate_parts()
        
        return page
        
    def _populate_parts(self):
        parts = self.svc.db.query(WorkOrderPart).filter(WorkOrderPart.work_order_id == self.wo_id).all()
        self.part_table.setRowCount(len(parts))
        for i, p in enumerate(parts):
            name = p.part.name if p.part else f"Part ID {p.part_id}"
            self.part_table.setItem(i, 0, QTableWidgetItem(name))
            self.part_table.setItem(i, 1, QTableWidgetItem(str(p.quantity_used)))
            cost = p.quantity_used * (p.part.unit_price if p.part else 0)
            self.part_table.setItem(i, 2, QTableWidgetItem(f"{cost:,.2f}"))
            
    def _add_part(self):
        dlg = AddPartDialog(self.wo_id, self.svc, self)
        if dlg.exec():
            self._populate_parts()
            
    def _show_suggestions(self):
        suggestions = self.svc.get_spare_part_suggestions(self.wo.machine_id, self.wo.failure_code)
        if not suggestions:
            QMessageBox.information(self, "ผลลัพธ์", "ไม่มีประวัติการใช้อะไหล่สำหรับอาการนี้หรือเครื่องจักรนี้")
            return
            
        msg = "💡 อะไหล่ที่แนะนำให้เบิก (อ้างอิงจากประวัติการซ่อมอาการเดียวกัน):\n\n"
        for s in suggestions:
            msg += f"- {s.code} / {s.name} (คงเหลือ: {s.current_stock})\n"
            
        QMessageBox.information(self, "Smart Suggestion", msg)
        
    def _tab_rca(self):
        page = QWidget()
        self.rca_lay = QFormLayout(page)
        self.whys = []
        for i in range(1, 6):
            w = QLineEdit(getattr(self.wo, f"root_cause_why{i}") or "")
            self.whys.append(w)
            self.rca_lay.addRow(f"Why {i}:", w)
            
        self.action_in = QTextEdit(getattr(self.wo, "action_taken") or "")
        self.rca_lay.addRow("Action Taken:", self.action_in)
        
        save_btn = QPushButton("บันทึก RCA")
        save_btn.clicked.connect(self._save_rca)
        self.rca_lay.addRow(save_btn)
        return page
        
    def _set_status(self, status, extra_data=None):
        data = {"status": status}
        if extra_data:
            data.update(extra_data)
        try:
            self.svc.update_work_order(self.wo.id, data)
            self._load_wo()
            self._build_ui()
            # We recreate the UI to refresh buttons. A bit hacky but works for dialog.
            QWidget().setLayout(self.layout()) # clear old layout
            self._build_ui()
            QMessageBox.information(self, "สำเร็จ", f"อัปเดตสถานะเป็น {status}")
        except Exception as e:
            QMessageBox.critical(self, "ข้อผิดพลาด", str(e))
            
    def _approve_wo(self):
        # Only Managers/Engineers should approve, handled implicitly or by RBAC
        self._set_status("Approved", {"is_approved": True})
        
    def _hold_wo(self):
        from PyQt6.QtWidgets import QInputDialog
        reason, ok = QInputDialog.getText(self, "พักงาน", "ระบุเหตุผลที่พักงาน (เช่น รออะไหล่):")
        if ok and reason:
            self._set_status("Hold", {"hold_reason": reason})
            
    def _done_wo(self):
        if self.wo.wo_type == 'Breakdown' and self.wo.priority in ['High', 'Critical']:
            why1 = self.whys[0].text() if hasattr(self, 'whys') else getattr(self.wo, 'root_cause_why1')
            if not why1:
                QMessageBox.warning(self, "แจ้งเตือน", "กรุณากรอก RCA (Why 1 เป็นอย่างน้อย) ก่อนแจ้งซ่อมเสร็จสำหรับงาน Breakdown")
                return
        self._set_status("Done")
        
    def _save_rca(self):
        data = {
            "root_cause_why1": self.whys[0].text(),
            "root_cause_why2": self.whys[1].text(),
            "root_cause_why3": self.whys[2].text(),
            "root_cause_why4": self.whys[3].text(),
            "root_cause_why5": self.whys[4].text(),
            "action_taken": self.action_in.toPlainText()
        }
        try:
            self.svc.update_work_order(self.wo.id, data)
            QMessageBox.information(self, "สำเร็จ", "บันทึก RCA เรียบร้อย")
        except Exception as e:
            QMessageBox.critical(self, "ข้อผิดพลาด", str(e))
            
    def _accept_wo(self):
        # Open User Acceptance Dialog
        dlg = UserAcceptanceDialog(self.wo_id, self)
        if dlg.exec():
            # Update status to Closed and capture rating
            data = dlg.get_data()
            data["status"] = "Closed"
            try:
                self.svc.update_work_order(self.wo.id, data)
                QMessageBox.information(self, "สำเร็จ", "ปิดงานสมบูรณ์แล้ว")
                self.accept() # Close the execution dialog completely
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", str(e))

class UserAcceptanceDialog(QDialog):
    def __init__(self, wo_id, parent=None):
        super().__init__(parent)
        self.setWindowTitle("ตรวจรับงาน")
        self.setFixedWidth(400)
        self._build_ui()
        
    def _build_ui(self):
        lay = QFormLayout(self)
        
        self.rating = QSpinBox()
        self.rating.setRange(1, 5)
        self.rating.setValue(5)
        lay.addRow("คะแนนความพึงพอใจ (1-5):", self.rating)
        
        self.note = QTextEdit()
        lay.addRow("ข้อเสนอแนะ:", self.note)
        
        btns = QHBoxLayout()
        sub = QPushButton("ยืนยันตรวจรับ")
        sub.setObjectName("btn_primary")
        sub.clicked.connect(self.accept)
        btns.addWidget(sub)
        lay.addRow(btns)
        
    def get_data(self):
        return {
            "requester_satisfaction_score": self.rating.value(),
            "requester_acceptance_note": self.note.toPlainText()
        }

class AddLaborDialog(QDialog):
    def __init__(self, wo_id, parent=None):
        super().__init__(parent)
        self.wo_id = wo_id
        self.svc = WorkOrderService()
        if hasattr(parent, 'svc') and hasattr(parent.svc, 'current_user_id'):
            self.svc.current_user_id = parent.svc.current_user_id
        self.setWindowTitle("บันทึกเวลาช่างเทคนิค")
        self.setFixedWidth(400)
        self._build_ui()
        
    def _build_ui(self):
        lay = QFormLayout(self)
        
        self.user_cb = QComboBox()
        users = self.svc.db.query(User).filter(User.is_active == True).all()
        for u in users:
            self.user_cb.addItem(f"{u.username} ({u.role})", u.id)
        lay.addRow("ช่างเทคนิค/พนักงาน:", self.user_cb)
        
        self.minutes_in = QSpinBox()
        self.minutes_in.setRange(1, 10000)
        self.minutes_in.setSuffix(" นาที")
        lay.addRow("เวลาปฏิบัติงาน:", self.minutes_in)
        
        self.rate_in = QDoubleSpinBox()
        self.rate_in.setRange(0, 10000)
        self.rate_in.setSuffix(" บาท/ชั่วโมง")
        lay.addRow("ค่าแรงชั่วโมงละ:", self.rate_in)
        
        btns = QHBoxLayout()
        submit = QPushButton("บันทึก")
        submit.setObjectName("btn_primary")
        submit.clicked.connect(self._save)
        btns.addWidget(submit)
        lay.addRow(btns)
        
    def _save(self):
        labor = WorkOrderLabor(
            work_order_id=self.wo_id,
            user_id=self.user_cb.currentData(),
            actual_minutes=self.minutes_in.value(),
            hourly_rate=self.rate_in.value()
        )
        self.svc.db.add(labor)
        self.svc.commit()
        self.accept()

class AddVendorDialog(QDialog):
    def __init__(self, wo_id, parent=None):
        super().__init__(parent)
        self.wo_id = wo_id
        self.svc = WorkOrderService()
        self.setWindowTitle("เพิ่มผู้รับเหมา / บริการนอก")
        self.setFixedWidth(400)
        self.quote_path = None
        self.report_path = None
        self._build_ui()
        
    def _build_ui(self):
        lay = QFormLayout(self)
        
        self.name_in = QLineEdit()
        lay.addRow("ชื่อ Vendor/ผู้รับเหมา:", self.name_in)
        
        self.cost_in = QDoubleSpinBox()
        self.cost_in.setRange(0, 1000000)
        self.cost_in.setSuffix(" บาท")
        lay.addRow("ค่าบริการรวม:", self.cost_in)
        
        # Files
        qr = QHBoxLayout()
        self.btn_quote = QPushButton("แนบใบเสนอราคา")
        self.btn_quote.clicked.connect(lambda: getattr(self, '_pick_file')('quote'))
        qr.addWidget(self.btn_quote)
        lay.addRow("Quote:", qr)
        
        sr = QHBoxLayout()
        self.btn_report = QPushButton("แนบ Service Report")
        self.btn_report.clicked.connect(lambda: getattr(self, '_pick_file')('report'))
        sr.addWidget(self.btn_report)
        lay.addRow("Report:", sr)
        
        btns = QHBoxLayout()
        submit = QPushButton("บันทึก")
        submit.setObjectName("btn_primary")
        submit.clicked.connect(self._save)
        btns.addWidget(submit)
        lay.addRow(btns)
        
    def _pick_file(self, ftype):
        path, _ = QFileDialog.getOpenFileName(self, "เลือกไฟล์", "", "All Files (*)")
        if path:
            if ftype == 'quote':
                self.quote_path = path
                self.btn_quote.setText("✔️ เลือกไฟล์แล้ว")
            else:
                self.report_path = path
                self.btn_report.setText("✔️ เลือกไฟล์แล้ว")
                
    def _save(self):
        if not self.name_in.text().strip():
            QMessageBox.warning(self, "แจ้งเตือน", "กรุณาระบุชื่อ Vendor")
            return
            
        import shutil, os
        from utils import config
        
        def copy_file(src):
            if not src: return None
            os.makedirs(config.UPLOAD_FOLDER, exist_ok=True)
            fname = os.path.basename(src)
            dest = os.path.join(config.UPLOAD_FOLDER, f"vendor_{self.wo_id}_{fname}")
            try:
                shutil.copy(src, dest)
                return dest
            except:
                return None
                
        q_path = copy_file(self.quote_path)
        r_path = copy_file(self.report_path)
        
        vendor = WorkOrderVendor(
            work_order_id=self.wo_id,
            vendor_name=self.name_in.text().strip(),
            service_cost=self.cost_in.value(),
            quote_file_path=q_path,
            report_file_path=r_path
        )
        self.svc.db.add(vendor)
        self.svc.commit()
        self.accept()

class AddPartDialog(QDialog):
    def __init__(self, wo_id, svc, parent=None):
        super().__init__(parent)
        self.wo_id = wo_id
        self.svc = svc
        self.setWindowTitle("เบิกอะไหล่")
        self.setFixedWidth(400)
        self._build_ui()
        
    def _build_ui(self):
        lay = QFormLayout(self)
        
        self.part_cb = QComboBox()
        parts = self.svc.db.query(SparePart).all()
        for p in parts:
            self.part_cb.addItem(f"{p.code} - {p.name} (เหลือ {p.current_stock})", p.id)
        lay.addRow("เลือกอะไหล่:", self.part_cb)
        
        self.qty_in = QSpinBox()
        self.qty_in.setRange(1, 1000)
        lay.addRow("จำนวนที่เบิก:", self.qty_in)
        
        btns = QHBoxLayout()
        sub = QPushButton("บันทึกเบิก")
        sub.setObjectName("btn_primary")
        sub.clicked.connect(self._save)
        btns.addWidget(sub)
        lay.addRow(btns)
        
    def _save(self):
        part_id = self.part_cb.currentData()
        qty = self.qty_in.value()
        
        part = self.svc.db.query(SparePart).filter(SparePart.id == part_id).first()
        if not part or part.current_stock < qty:
            QMessageBox.warning(self, "ผิดพลาด", "อะไหล่ในคลังไม่เพียงพอ")
            return
            
        part.current_stock -= qty # Deduct stock
        
        wo_part = WorkOrderPart(
            work_order_id=self.wo_id,
            part_id=part_id,
            quantity_used=qty
        )
        self.svc.db.add(wo_part)
        self.svc.commit()
        self.accept()

class WorkOrderCard(QFrame):
    def __init__(self, wo, parent_page=None):
        super().__init__()
        self.wo = wo
        self.parent_page = parent_page
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setObjectName("card")
        self.setStyleSheet("""
            QFrame#card {
                background-color: white;
                border: 1px solid #dcdcdc;
                border-radius: 6px;
                margin-bottom: 4px;
            }
            QFrame#card:hover {
                border: 1px solid #1976d2;
                background-color: #f8fbff;
            }
        """)

        lay = QVBoxLayout(self)
        lay.setContentsMargins(12, 12, 12, 12)
        lay.setSpacing(6)
        
        # Header: ID + Priority
        hl = QHBoxLayout()
        id_lbl = QLabel(f"<b>WO-{wo.id:04d}</b>")
        id_lbl.setStyleSheet("color: #1976d2; font-size: 14px;")
        hl.addWidget(id_lbl)
        hl.addStretch()
        prio_color = {"Critical": "red", "High": "orange", "Normal": "#388e3c", "Low": "gray"}.get(wo.priority, "black")
        prio_lbl = QLabel(f"{wo.priority}")
        prio_lbl.setStyleSheet(f"color: {prio_color}; font-weight: bold; font-size: 11px; padding: 2px 6px; border: 1px solid {prio_color}; border-radius: 4px;")
        hl.addWidget(prio_lbl)
        lay.addLayout(hl)
        
        # Type & Machine
        machine_name = wo.machine.name if wo.machine else "ทั่วไป (General)"
        type_str = f"ประเภท: {wo.wo_type}"
        type_lbl = QLabel(type_str)
        type_lbl.setWordWrap(True)
        type_lbl.setStyleSheet("font-size: 13px; color: #333;")
        lay.addWidget(type_lbl)
        
        mach_lbl = QLabel(f"พท./เครื่องจักร: {machine_name}")
        mach_lbl.setWordWrap(True)
        mach_lbl.setStyleSheet("color: #666; font-size: 12px;")
        lay.addWidget(mach_lbl)
        
        # Issue / Origin
        desc = wo.description if wo.description else ""
        if len(desc) > 60: desc = desc[:60] + "..."
        desc_lbl = QLabel(desc)
        desc_lbl.setWordWrap(True)
        desc_lbl.setStyleSheet("color: #444; font-size: 12px; font-style: italic;")
        lay.addWidget(desc_lbl)
        
        lay.addStretch()
        
        # Actions
        btn_lay = QHBoxLayout()
        btn_lay.setContentsMargins(0, 8, 0, 0)
        
        # Admin Actions
        if getattr(self.parent_page.current_user, 'role', '') == 'Admin':
            edit_btn = QPushButton("✏️ แก้ไข")
            edit_btn.setObjectName("btn_small")
            edit_btn.setCursor(Qt.CursorShape.PointingHandCursor)
            edit_btn.clicked.connect(lambda: getattr(self.parent_page, '_edit_wo')(self.wo))
            btn_lay.addWidget(edit_btn)
            
            del_btn = QPushButton("🗑️ ลบ")
            del_btn.setObjectName("btn_danger_small") # Fallback to warning style
            del_btn.setStyleSheet("color: white; background-color: #d32f2f; border: none; padding: 4px 8px; border-radius: 3px;")
            del_btn.setCursor(Qt.CursorShape.PointingHandCursor)
            del_btn.clicked.connect(lambda: getattr(self.parent_page, '_delete_wo')(self.wo.id))
            btn_lay.addWidget(del_btn)
            
        btn_lay.addStretch()
        view_btn = QPushButton("👁️ จัดการ")
        view_btn.setObjectName("btn_small")
        view_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        view_btn.clicked.connect(lambda: getattr(self.parent_page, '_manage_wo')(self.wo))
        btn_lay.addWidget(view_btn)
        
        prt_btn = QPushButton("🖨️ พิมพ์")
        prt_btn.setObjectName("btn_small")
        prt_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        prt_btn.clicked.connect(lambda: getattr(self.parent_page, '_print_wo')(self.wo.id))
        btn_lay.addWidget(prt_btn)
        
        lay.addLayout(btn_lay)
