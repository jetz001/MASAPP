# ============================================================
#  Maintenance Super App v3.3  –  views.py
#  Modern Dark-Theme UI with Sidebar Navigation
# ============================================================

import os
import sys
from PyQt6.QtWidgets import (
    QMainWindow, QLabel, QVBoxLayout, QHBoxLayout, QWidget,
    QTabWidget, QPushButton, QTableWidget, QTableWidgetItem,
    QHeaderView, QLineEdit, QFormLayout, QDialog, QMessageBox,
    QFrame, QSizePolicy, QStackedWidget, QSpacerItem, QCheckBox,
    QScrollArea, QComboBox, QDateEdit, QFileDialog, QTextEdit
)
from PyQt6.QtCore import Qt, QSize, QEasingCurve, QDate, QPoint, QLocale
from PyQt6.QtCore import QPropertyAnimation, QRect
from PyQt6.QtGui import QFont, QColor, QPalette, QIcon, QPixmap
import pprint
import models
from datetime import datetime

from services import (
    UserService, MachineService, IntakeFormService, SettingsService, FactoryMapService, PMService, WorkOrderService, ReportingService,
    can, PERMISSIONS, ROLE_ADMIN, ROLE_MANAGER, ROLE_ENGINEER, ROLE_TECHNICIAN, ROLE_VIEWER, ALL_ROLES, ROLE_META
)
from models import User, Machine, PMPlan, WorkOrder, SparePart, WorkOrderPart, WorkPermit, FactoryMap, MachineIntakeForm
from factory_layout import FactoryLayoutPage


# ─────────────────────────────────────────────────────────────
#  Theme Manager  –  สลับ Light / Dark ได้
# ─────────────────────────────────────────────────────────────
THEMES = {
    "dark": {
        "name":         "Dark Mode",
        "icon":         "🌙",
        "BG_DARK":      "#0D1117",
        "BG_PANEL":     "#161B22",
        "BG_CARD":      "#21262D",
        "ACCENT":       "#238636",
        "ACCENT_HOVER": "#2EA043",
        "ACCENT_LIGHT": "#56D364",
        "TEXT_PRIMARY": "#E6EDF3",
        "TEXT_MUTED":   "#8B949E",
        "BORDER":       "#30363D",
        "RED":          "#F85149",
        "YELLOW":       "#D29922",
        "BLUE":         "#388BFD",
        "NAV_ACTIVE_BG":"rgba(35,134,54,0.18)",
    },
    "light": {
        "name":         "Light Mode",
        "icon":         "☀️",
        "BG_DARK":      "#EEF2F7",
        "BG_PANEL":     "#FFFFFF",
        "BG_CARD":      "#F0F4F8",
        "ACCENT":       "#1565C0",
        "ACCENT_HOVER": "#1976D2",
        "ACCENT_LIGHT": "#1565C0",
        "TEXT_PRIMARY": "#1A1A2E",
        "TEXT_MUTED":   "#5A6A7A",
        "BORDER":       "#C8D3DF",
        "RED":          "#D32F2F",
        "YELLOW":       "#F57C00",
        "BLUE":         "#1565C0",
        "NAV_ACTIVE_BG":"rgba(21,101,192,0.12)",
    },
}


def _build_qss(t: dict) -> str:
    return f"""
QMainWindow, QDialog {{
    background: {t['BG_DARK']};
}}
QWidget {{
    background: transparent;
    color: {t['TEXT_PRIMARY']};
    font-family: 'Segoe UI', 'Tahoma', sans-serif;
    font-size: 13px;
}}
QLabel {{ color: {t['TEXT_PRIMARY']}; }}

#sidebar {{
    background: {t['BG_PANEL']};
    border-right: 1px solid {t['BORDER']};
    min-width: 220px; max-width: 220px;
}}
QPushButton#nav_btn {{
    background: transparent;
    color: {t['TEXT_MUTED']};
    text-align: left; padding: 10px 16px;
    border: none; font-size: 13px; border-radius: 0;
}}
QPushButton#nav_btn:hover {{
    background: {t['BG_CARD']}; color: {t['TEXT_PRIMARY']};
}}
QPushButton#nav_btn_active {{
    background: {t['NAV_ACTIVE_BG']};
    color: {t['ACCENT_LIGHT']};
    text-align: left; padding: 10px 16px;
    border: none; border-left: 3px solid {t['ACCENT_LIGHT']};
    font-size: 13px; font-weight: 600; border-radius: 0;
}}
#content_area {{ background: {t['BG_DARK']}; }}
QFrame#card {{
    background: {t['BG_PANEL']};
    border: 1px solid {t['BORDER']}; border-radius: 8px;
}}
QTableWidget {{
    background: {t['BG_PANEL']};
    border: 1px solid {t['BORDER']}; border-radius: 6px;
    gridline-color: {t['BORDER']};
    selection-background-color: rgba(21,101,192,0.18);
}}
QTableWidget::item {{
    padding: 8px 10px; border: none; color: {t['TEXT_PRIMARY']};
}}
QTableWidget::item:selected {{ background: rgba(21,101,192,0.18); }}
QTableWidget::item:alternate {{ background: {t['BG_CARD']}; }}
QHeaderView::section {{
    background: {t['BG_CARD']}; color: {t['TEXT_MUTED']};
    font-weight: 600; font-size: 11px;
    padding: 10px; border: none;
    border-bottom: 1px solid {t['BORDER']};
}}
QPushButton#btn_primary {{
    background: {t['ACCENT']}; color: #ffffff;
    border: none; border-radius: 6px;
    padding: 8px 18px; font-weight: 600; font-size: 13px;
}}
QPushButton#btn_primary:hover {{ background: {t['ACCENT_HOVER']}; }}
QPushButton#btn_secondary {{
    background: {t['BG_CARD']}; color: {t['TEXT_PRIMARY']};
    border: 1px solid {t['BORDER']}; border-radius: 6px;
    padding: 8px 18px; font-size: 13px;
}}
QPushButton#btn_secondary:hover {{
    border-color: {t['BLUE']}; color: {t['BLUE']};
}}
QPushButton#btn_danger {{
    background: transparent; color: {t['RED']};
    border: 1px solid {t['RED']}; border-radius: 6px;
    padding: 5px 12px; font-size: 12px;
}}
QPushButton#btn_small {{
    background: {t['BG_CARD']}; color: {t['TEXT_PRIMARY']};
    border: 1px solid {t['BORDER']}; border-radius: 4px;
    padding: 4px 10px; font-size: 11px;
}}
QPushButton#btn_small:hover {{
    border-color: {t['ACCENT']}; color: {t['ACCENT_LIGHT']};
}}
QLineEdit, QComboBox, QDateEdit, QTextEdit {{
    background: {t['BG_CARD']}; border: 1px solid {t['BORDER']};
    border-radius: 6px; color: {t['TEXT_PRIMARY']};
    padding: 7px 10px; font-size: 13px;
}}
QLineEdit:focus, QComboBox:focus, QTextEdit:focus {{
    border-color: {t['BLUE']};
}}

QCheckBox {{
    spacing: 8px;
    font-size: 13px;
    color: {t['TEXT_PRIMARY']};
    background: transparent;
}}
QCheckBox::indicator {{
    width: 18px; height: 18px;
    border: 1.5px solid {t['BORDER']};
    border-radius: 4px;
    background: {t['BG_CARD']};
}}
QCheckBox::indicator:hover {{
    border-color: {t['ACCENT']};
}}
QCheckBox::indicator:checked {{
    background: {t['ACCENT']};
    border-color: {t['ACCENT']};
    image: url(assets/check.svg);
}}

QScrollBar:vertical {{
    background: {t['BG_PANEL']}; width: 8px; margin: 0;
}}
QScrollBar::handle:vertical {{
    background: {t['BORDER']}; border-radius: 4px; min-height: 30px;
}}
QScrollBar::handle:vertical:hover {{ background: {t['TEXT_MUTED']}; }}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}
QScrollBar:horizontal {{
    background: {t['BG_PANEL']}; height: 8px;
}}
QScrollBar::handle:horizontal {{
    background: {t['BORDER']}; border-radius: 4px;
}}
QDialog {{
    background: {t['BG_PANEL']};
    border: 1px solid {t['BORDER']}; border-radius: 8px;
}}
QMessageBox {{ background: {t['BG_PANEL']}; }}
QMessageBox QPushButton {{
    background-color: {t['BG_CARD']};
    color: {t['TEXT_PRIMARY']} !important;
    border: 1px solid {t['BORDER']};
    border-radius: 6px;
    padding: 6px 18px; 
    min-width: 80px;
    font-weight: 600;
}}
QMessageBox QPushButton:hover {{
    border-color: {t['ACCENT']};
    color: {t['ACCENT']};
}}
"""


class ThemeManager:
    _current = "light"   # ⭐ start in Light (blue/white) mode by default
    _app_ref = None
    _win_ref = None

    @classmethod
    def set_app(cls, app):
        cls._app_ref = app

    @classmethod
    def current(cls) -> dict:
        return THEMES[cls._current]

    @classmethod
    def current_key(cls) -> str:
        return cls._current

    @classmethod
    def qss(cls) -> str:
        return _build_qss(cls.current())

    @classmethod
    def toggle(cls, window=None):
        """Switch between dark and light themes dynamically."""
        cls._current = "light" if cls._current == "dark" else "dark"
        # Update module-level globals so inline setStyleSheet calls use new colours
        cls._apply_globals()
        qss = cls.qss()
        if cls._app_ref:
            cls._app_ref.setStyleSheet(qss)
        
        # Recreate the window so all widgets rebuild with the new colours
        if window:
            user = window._current_user
            window.close()
            new_win = MainWindow(user=user)
            new_win.show()
            # Store reference so GC doesn't collect it
            cls._win_ref = new_win

    @classmethod
    def _apply_globals(cls):
        """Push current theme colours into module-level constants."""
        import views as _v
        t = cls.current()
        _v.BG_DARK      = t["BG_DARK"]
        _v.BG_PANEL     = t["BG_PANEL"]
        _v.BG_CARD      = t["BG_CARD"]
        _v.ACCENT       = t["ACCENT"]
        _v.ACCENT_HOVER = t["ACCENT_HOVER"]
        _v.ACCENT_LIGHT = t["ACCENT_LIGHT"]
        _v.TEXT_PRIMARY = t["TEXT_PRIMARY"]
        _v.TEXT_MUTED   = t["TEXT_MUTED"]
        _v.BORDER       = t["BORDER"]
        _v.RED          = t["RED"]
        _v.YELLOW       = t["YELLOW"]
        _v.BLUE         = t["BLUE"]
        _v.QSS_GLOBAL   = _build_qss(t)

    @classmethod
    def c(cls, key: str) -> str:
        """Shorthand: ThemeManager.c('ACCENT') → current accent colour."""
        return cls.current()[key]


# Global colour helpers (always reads CURRENT theme)
def _c(key):
    return ThemeManager.c(key)


# Stable aliases — initialised from the default (light) theme
# These get updated by ThemeManager._apply_globals() on every toggle.
_light = THEMES["light"]
BG_DARK      = _light["BG_DARK"]
BG_PANEL     = _light["BG_PANEL"]
BG_CARD      = _light["BG_CARD"]
ACCENT       = _light["ACCENT"]
ACCENT_HOVER = _light["ACCENT_HOVER"]
ACCENT_LIGHT = _light["ACCENT_LIGHT"]
TEXT_PRIMARY = _light["TEXT_PRIMARY"]
TEXT_MUTED   = _light["TEXT_MUTED"]
BORDER       = _light["BORDER"]
RED          = _light["RED"]
YELLOW       = _light["YELLOW"]
BLUE         = _light["BLUE"]

# QSS_GLOBAL: generated dynamically, also updated on toggle
QSS_GLOBAL = _build_qss(_light)




# ─── Login Dialog ─────────────────────────────────────────────
class LoginDialog(QDialog):
    """Shown before MainWindow. Returns the authenticated User."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("เข้าสู่ระบบ — Maintenance Super App v3.3")
        self.setFixedSize(440, 560)
        # ✅ ไม่ใช้ FramelessWindowHint → มีปุ่ม X ตามปกติ
        self.setStyleSheet(ThemeManager.qss())
        self.authenticated_user = None
        self._service = UserService()
        from PyQt6.QtCore import QSettings
        self.settings = QSettings("MASAPP", "MaintenanceSuperApp")
        self._build_ui()

    # input style: light-bg so typed text is clearly readable
    _INPUT_STYLE = (
        "background: #F0F4F8; color: #1A1A2E;"
        "border: 1.5px solid #30363D; border-radius: 6px;"
        "padding: 8px 12px; font-size: 14px;"
    )

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── Banner / Header
        banner = QWidget()
        banner.setFixedHeight(150)
        banner.setStyleSheet(
            f"background: qlineargradient(x1:0,y1:0,x2:1,y2:1,"
            f"stop:0 {ACCENT}, stop:1 #1a6b2e);"
        )
        bl = QVBoxLayout(banner)
        bl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        bl.setSpacing(6)
        ico = QLabel()
        _logo_p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "masapp_logo.png")
        if os.path.exists(_logo_p):
            from PyQt6.QtGui import QPixmap
            _pix = QPixmap(_logo_p).scaledToHeight(64, Qt.TransformationMode.SmoothTransformation)
            ico.setPixmap(_pix)
        else:
            ico.setText("⚙")
            ico.setFont(QFont("Segoe UI", 28))
        ico.setAlignment(Qt.AlignmentFlag.AlignCenter)
        ico.setStyleSheet("background: transparent;")
        title = QLabel("MASAPP")
        title.setFont(QFont("Segoe UI", 22, QFont.Weight.Bold))
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.setStyleSheet("background: transparent; color: white; letter-spacing: 3px;")
        sub = QLabel("Maintenance Super App v3.3")
        sub.setAlignment(Qt.AlignmentFlag.AlignCenter)
        sub.setStyleSheet("background: transparent; color: rgba(255,255,255,0.8); font-size: 12px;")
        bl.addWidget(ico); bl.addWidget(title); bl.addWidget(sub)
        root.addWidget(banner)

        # ── Form area
        form_w = QWidget()
        form_w.setStyleSheet(f"background: {BG_PANEL};")
        fl = QVBoxLayout(form_w)
        fl.setContentsMargins(40, 28, 40, 28)
        fl.setSpacing(10)

        heading = QLabel("เข้าสู่ระบบ")
        heading.setFont(QFont("Segoe UI", 16, QFont.Weight.Bold))
        heading.setStyleSheet(f"color: {TEXT_PRIMARY}; background: transparent;")
        fl.addWidget(heading)
        fl.addSpacing(8)

        # Username
        u_lbl = QLabel("ชื่อผู้ใช้")
        u_lbl.setStyleSheet(f"color: {TEXT_MUTED}; background: transparent; font-size: 12px;")
        self.username_input = QLineEdit()
        self.username_input.setPlaceholderText("กรอกชื่อผู้ใช้")
        self.username_input.setStyleSheet(self._INPUT_STYLE)
        self.username_input.returnPressed.connect(self._do_login)
        saved_user = self.settings.value("login_username", "")
        if saved_user:
            self.username_input.setText(saved_user)

        # Password
        pw_lbl = QLabel("รหัสผ่าน")
        pw_lbl.setStyleSheet(f"color: {TEXT_MUTED}; background: transparent; font-size: 12px;")
        self.password_input = QLineEdit()
        self.password_input.setPlaceholderText("กรอกรหัสผ่าน")
        self.password_input.setEchoMode(QLineEdit.EchoMode.Password)
        self.password_input.setFixedHeight(44)
        self.password_input.setStyleSheet(self._INPUT_STYLE)
        self.password_input.returnPressed.connect(self._do_login)
        saved_pass = self.settings.value("login_password", "")
        if saved_pass:
            self.password_input.setText(saved_pass)

        self.show_pw_btn = QPushButton("👁")
        self.show_pw_btn.setFixedSize(44, 44)
        self.show_pw_btn.setCheckable(True)
        self.show_pw_btn.setStyleSheet(
            "background: #E0E8EF; color: #333; border: 1.5px solid #30363D;"
            "border-radius: 6px; font-size: 16px;"
        )
        self.show_pw_btn.toggled.connect(
            lambda chk: self.password_input.setEchoMode(
                QLineEdit.EchoMode.Normal if chk else QLineEdit.EchoMode.Password
            )
        )
        pw_row = QHBoxLayout()
        pw_row.setSpacing(6)
        pw_row.addWidget(self.password_input)
        pw_row.addWidget(self.show_pw_btn)

        # Error label
        self.error_lbl = QLabel("")
        self.error_lbl.setStyleSheet(
            f"color: {RED}; background: rgba(248,81,73,0.12);"
            f"border: 1px solid {RED}; border-radius: 6px;"
            f"padding: 6px 10px; font-size: 12px;"
        )
        self.error_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.error_lbl.hide()

        # Remember Me
        from PyQt6.QtWidgets import QCheckBox
        self.remember_cb = QCheckBox("จดจำฉันไว้ (Remember Me)")
        self.remember_cb.setStyleSheet(f"color: {TEXT_MUTED}; font-size: 13px; background: transparent;")
        if saved_user and saved_pass:
            self.remember_cb.setChecked(True)

        # Login button
        self.login_btn = QPushButton("  เข้าสู่ระบบ  ")
        self.login_btn.setFixedHeight(46)
        self.login_btn.setStyleSheet(
            f"background: {ACCENT}; color: white; border-radius: 8px;"
            f"font-size: 15px; font-weight: 700; border: none;"
        )
        self.login_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.login_btn.clicked.connect(self._do_login)

        fl.addWidget(u_lbl); fl.addWidget(self.username_input)
        fl.addSpacing(4)
        fl.addWidget(pw_lbl); fl.addLayout(pw_row)
        fl.addSpacing(6)
        fl.addWidget(self.error_lbl)
        fl.addWidget(self.remember_cb)
        fl.addSpacing(6)
        fl.addWidget(self.login_btn)
        fl.addStretch()

        hint = QLabel("ติดต่อ Admin หากลืมรหัสผ่าน")
        hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hint.setStyleSheet(f"color: {TEXT_MUTED}; font-size: 11px; background: transparent;")
        fl.addWidget(hint)
        root.addWidget(form_w)

    def _do_login(self):
        username = self.username_input.text().strip()
        password = self.password_input.text()
        if not username or not password:
            self._show_error("กรุณากรอกชื่อผู้ใช้และรหัสผ่าน")
            return
        self.login_btn.setText("กำลังตรวจสอบ...")
        self.login_btn.setEnabled(False)
        user = self._service.login(username, password)
        if user:
            if self.remember_cb.isChecked():
                self.settings.setValue("login_username", username)
                self.settings.setValue("login_password", password)
            else:
                self.settings.remove("login_username")
                self.settings.remove("login_password")
            self.authenticated_user = user
            self.accept()
        else:
            self.login_btn.setText("  เข้าสู่ระบบ  ")
            self.login_btn.setEnabled(True)
            self._show_error("ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง")
            self.password_input.clear()
            self.password_input.setFocus()

    def _show_error(self, msg):
        self.error_lbl.setText(f"⚠  {msg}")
        self.error_lbl.show()


# ─── Helper: Section header label ─────────────────────────────
def make_label(text, size=13, bold=False, color=TEXT_PRIMARY):
    lbl = QLabel(text)
    f = QFont("Segoe UI", size)
    f.setBold(bold)
    lbl.setFont(f)
    lbl.setStyleSheet(f"color: {color}; background: transparent;")
    return lbl


def make_separator():
    line = QFrame()
    line.setFrameShape(QFrame.Shape.HLine)
    line.setStyleSheet(f"color: {BORDER}; background: {BORDER}; max-height: 1px;")
    return line


# ─── Add Machine Dialog ────────────────────────────────────────
class AddMachineDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("เพิ่มเครื่องจักรใหม่")
        self.setMinimumWidth(440)
        self.setStyleSheet(f"QDialog {{ background: {BG_PANEL}; }}")

        root = QVBoxLayout(self)
        root.setContentsMargins(24, 24, 24, 24)
        root.setSpacing(12)

        # Title
        root.addWidget(make_label("เพิ่มเครื่องจักรใหม่", 16, bold=True, color=TEXT_PRIMARY))
        root.addWidget(make_separator())

        form = QFormLayout()
        form.setSpacing(10)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)

        def field(ph=""):
            e = QLineEdit()
            e.setPlaceholderText(ph)
            return e

        self.code_input   = field("MA-001")
        self.name_input   = field("ชื่อเครื่องจักร")
        self.model_input  = field("รุ่น / Model")
        self.serial_input = field("S/N ...")
        self.zone_input   = field("เช่น STOCK FG, บำบัดน้ำเสีย")
        self.resp_input   = field("ชื่อผู้รับผิดชอบ")

        lbl_style = f"color: {TEXT_MUTED}; background: transparent;"
        for lbl_txt, widget in [
            ("รหัสเครื่องจักร *", self.code_input),
            ("ชื่อเครื่องจักร *",  self.name_input),
            ("รุ่น (Model)",       self.model_input),
            ("Serial Number",      self.serial_input),
            ("โซน (Zone)",         self.zone_input),
            ("ผู้รับผิดชอบ",        self.resp_input),
        ]:
            lbl = QLabel(lbl_txt)
            lbl.setStyleSheet(lbl_style)
            form.addRow(lbl, widget)

        root.addLayout(form)
        root.addSpacing(8)

        # Buttons row
        btn_row = QHBoxLayout()
        btn_row.addStretch()

        self.cancel_btn = QPushButton("ยกเลิก")
        self.cancel_btn.setObjectName("btn_secondary")
        self.cancel_btn.clicked.connect(self.reject)
        btn_row.addWidget(self.cancel_btn)

        self.save_btn = QPushButton("  บันทึก  ")
        self.save_btn.setObjectName("btn_primary")
        self.save_btn.clicked.connect(self.accept)
        btn_row.addWidget(self.save_btn)

        root.addLayout(btn_row)


# ─── View Machine Dialog ────────────────────────────────────────
class ViewMachineDialog(QDialog):
    def __init__(self, machine, parent=None):
        super().__init__(parent)
        self.machine = machine
        self.setWindowTitle(f"ข้อมูลเครื่องจักร: {machine.code}")
        self.setMinimumWidth(550)
        self.setStyleSheet(f"QDialog {{ background: {BG_PANEL}; }}")
        
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 24, 24, 24)
        root.setSpacing(16)
        
        # Header
        hdr = QHBoxLayout()
        hdr.addWidget(make_label("ข้อมูลเครื่องจักร", 16, bold=True, color=TEXT_PRIMARY))
        
        status_color = {"Running": ACCENT_LIGHT, "Warning": YELLOW, "Breakdown": RED}.get(machine.status, TEXT_MUTED)
        st_lbl = QLabel(f" {machine.status or 'Running'} ")
        st_lbl.setStyleSheet(f"color: {status_color}; border: 1px solid {status_color}; border-radius: 6px; padding: 2px 8px; font-weight: bold;")
        hdr.addStretch()
        hdr.addWidget(st_lbl)
        root.addLayout(hdr)
        root.addWidget(make_separator())
        
        # Content Layout
        grid = QFormLayout()
        grid.setSpacing(12)
        grid.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        
        lbl_style = f"color: {TEXT_MUTED}; font-weight: bold; font-size: 13px;"
        val_style = f"color: {TEXT_PRIMARY}; font-size: 13px;"
        
        def add_row(lbl_text, val_text):
            l = QLabel(lbl_text); l.setStyleSheet(lbl_style)
            v = QLabel(str(val_text) if val_text else "–"); v.setStyleSheet(val_style)
            v.setWordWrap(True)
            grid.addRow(l, v)
        
        add_row("รหัสเครื่องจักร:", machine.code)
        add_row("ชื่อเครื่องจักร:", machine.name)
        add_row("ผู้รับผิดชอบ:", machine.responsible_person if hasattr(machine, 'responsible_person') else None)
        add_row("รุ่น / ยี่ห้อ:", machine.model)
        add_row("Serial Number:", machine.serial_number)
        add_row("โซน:", machine.zone)
        add_row("สเปคไฟฟ้าและขนาด:", f"กำลังไฟ: {machine.power_kw or '–'} kW | แรงดัน: {machine.voltage_v or '–'} V | กระแส: {machine.current_amp or '–'} A | เฟส: {machine.phase or 3} เฟส\nขนาด: {machine.dimensions or '–'}")
        
        supp = f"{machine.supplier_name or '–'}\nเบอร์ติดต่อ: {machine.supplier_contact or '–'}\nเซลล์: {machine.supplier_sales or '–'} | ประกัน: {machine.warranty_months or '–'} เดือน"
        add_row("ซัพพลายเออร์:", supp)
        
        root.addLayout(grid)
        root.addWidget(make_separator())
        
        # Documents Section
        doc_lbl = make_label("เอกสารแนบ", 13, bold=True)
        root.addWidget(doc_lbl)
        
        doc_layout = QHBoxLayout()
        doc_layout.setSpacing(8)
        
        def make_doc_btn(text, path):
            btn = QPushButton(text)
            btn.setObjectName("btn_secondary")
            btn.setFixedHeight(30)
            if path and os.path.exists(path):
                btn.clicked.connect(lambda _, p=path: os.startfile(p))
            else:
                btn.setEnabled(False)
                btn.setToolTip("ไม่พบไฟล์เอกสาร")
                btn.setStyleSheet(f"color: {TEXT_MUTED};")
            return btn
        
        # Pull associated intake form documents if available
        train_path = getattr(machine, 'training_file_path', None)
        approval_path = None
        if hasattr(machine, 'intake_form_id') and machine.intake_form_id:
            from services import IntakeFormService
            f_svc = IntakeFormService()
            frm = f_svc.get_form(machine.intake_form_id)
            if frm:
                if not train_path:
                    train_path = frm.training_file_path
                approval_path = frm.signed_form_path
                
        doc_layout.addWidget(make_doc_btn("📖 เปิดคู่มือ", machine.manual_file_path))
        doc_layout.addWidget(make_doc_btn("🎓 เอกสารอบรม", train_path))
        doc_layout.addWidget(make_doc_btn("✅ เอกสารอนุมัติ", approval_path))
        doc_layout.addStretch()
        
        root.addLayout(doc_layout)
        root.addSpacing(12)
        
        # Close Button
        btn_row = QHBoxLayout()
        btn_row.addStretch()
        
        print_btn = QPushButton("🖨 ปริ้นป้ายเครื่องจักร (A5)")
        print_btn.setObjectName("btn_secondary")
        print_btn.clicked.connect(self._print_label)
        btn_row.addWidget(print_btn)
        
        close_btn = QPushButton("ปิดหน้าต่าง")
        close_btn.setObjectName("btn_primary")
        close_btn.clicked.connect(self.accept)
        btn_row.addWidget(close_btn)
        root.addLayout(btn_row)

    def _print_label(self):
        from PyQt6.QtPrintSupport import QPrinter, QPrintPreviewDialog
        from PyQt6.QtGui import QPainter, QPageSize, QPageLayout, QFont, QPixmap, QImage, QColor, QPen
        from PyQt6.QtCore import QRect, QRectF, Qt
        from services import SettingsService
        import os, qrcode

        m = self.machine

        # ── Generate QR Code image ──
        qr_content = (
            f"MACHINE:{m.code}\n"
            f"NAME:{m.name}\n"
            f"SUPPLIER:{m.supplier_name or ''}\n"
            f"TEL:{m.supplier_contact or ''}\n"
            f"PHASE:{m.phase or 3} Phase\n"
            f"POWER:{m.power_kw or ''} kW"
        )
        qr = qrcode.QRCode(version=2, box_size=7, border=2,
                           error_correction=qrcode.constants.ERROR_CORRECT_M)
        qr.add_data(qr_content)
        qr.make(fit=True)
        qr_img = qr.make_image(fill_color="black", back_color="white")
        qr_dir = os.path.join("assets", "qrcodes")
        os.makedirs(qr_dir, exist_ok=True)
        qr_path = os.path.join(qr_dir, f"{m.code}_label.png")
        qr_img.save(qr_path)

        qr_pixmap = QPixmap(qr_path)

        # ── Logo ──
        logo_pixmap = None
        logo = SettingsService.get_setting("company_logo_path")
        if logo and os.path.exists(os.path.abspath(logo)):
            logo_pixmap = QPixmap(os.path.abspath(logo))

        # ── Printer setup ──
        printer = QPrinter(QPrinter.PrinterMode.HighResolution)
        printer.setPageSize(QPageSize(QPageSize.PageSizeId.A5))
        printer.setPageOrientation(QPageLayout.Orientation.Portrait)

        def paint_label(pr):
            painter = QPainter(pr)
            dpi = int(pr.resolution())
            pw = int(pr.pageRect(QPrinter.Unit.DevicePixel).width())
            ph = int(pr.pageRect(QPrinter.Unit.DevicePixel).height())

            margin = int(0.12 * dpi)
            x0, y0 = margin, margin
            avail_w = pw - 2 * margin
            avail_h = ph - 2 * margin
            inner_pad = int(0.06 * dpi)
            x1 = x0 + inner_pad
            inner_w = avail_w - 2 * inner_pad

            # ── Draw outer border ──
            painter.setPen(QPen(QColor("#000000"), int(dpi * 0.012)))
            painter.drawRect(x0, y0, avail_w, avail_h)
            y = y0 + inner_pad

            # ── Logo (centered) ──
            if logo_pixmap and not logo_pixmap.isNull():
                logo_h = int(0.25 * dpi)
                scaled_logo = logo_pixmap.scaledToHeight(logo_h, Qt.TransformationMode.SmoothTransformation)
                lx = x0 + (avail_w - scaled_logo.width()) // 2
                painter.drawPixmap(lx, y, scaled_logo)
                y += logo_h + int(0.05 * dpi)

            # ── Separator ──
            painter.setPen(QPen(QColor("#000000"), int(dpi * 0.008)))
            painter.drawLine(x0, y, x0 + avail_w, y)
            y += int(0.04 * dpi)

            # ── Title ──
            tf = QFont("TH Sarabun New", 0)
            tf.setPixelSize(int(dpi * 0.28))
            tf.setBold(True)
            painter.setFont(tf)
            painter.setPen(QColor("#000000"))
            trt = QRect(x1, y, inner_w, int(dpi * 0.34))
            painter.drawText(trt, Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignVCenter,
                             f"{m.code}   {m.name}")
            y += int(dpi * 0.34)

            # ── Separator ──
            painter.setPen(QPen(QColor("#000000"), int(dpi * 0.008)))
            painter.drawLine(x0, y, x0 + avail_w, y)
            y += int(0.04 * dpi)

            # ── Compact info rows (label + value on same line) ──
            lbl_font = QFont("TH Sarabun New", 0)
            lbl_font.setPixelSize(int(dpi * 0.13))
            lbl_font.setBold(True)
            val_font = QFont("TH Sarabun New", 0)
            val_font.setPixelSize(int(dpi * 0.13))
            val_font.setBold(False)

            resp      = m.responsible_person or "................................."
            supplier  = m.supplier_name     or "-"
            phone     = m.supplier_contact  or "-"
            phase_str = f"{m.phase or 3} เฟส  |  {m.power_kw or '-'} kW"

            rows = [
                ("ผู้รับผิดชอบ:", resp),
                ("ซัพพลายเออร์:", supplier),
                ("เบอร์โทร:", phone),
                ("ระบบไฟฟ้า:", phase_str),
            ]
            row_h = int(dpi * 0.20)
            lbl_col_w = int(inner_w * 0.35)

            for lbl_text, val_text in rows:
                painter.setFont(lbl_font)
                painter.setPen(QColor("#333333"))
                painter.drawText(QRect(x1, y, lbl_col_w, row_h),
                                 Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter, lbl_text)
                painter.setFont(val_font)
                painter.setPen(QColor("#000000"))
                painter.drawText(QRect(x1 + lbl_col_w, y, inner_w - lbl_col_w, row_h),
                                 Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter, val_text)
                y += row_h

            y += int(0.04 * dpi)
            # ── Separator ──
            painter.setPen(QPen(QColor("#000000"), int(dpi * 0.006)))
            painter.drawLine(x0, y, x0 + avail_w, y)
            y += int(0.04 * dpi)

            # ── Large QR code filling remaining space ──
            remaining_h = (y0 + avail_h - inner_pad) - y
            qr_size = min(avail_w - 2 * inner_pad, remaining_h)
            scaled_qr = qr_pixmap.scaled(qr_size, qr_size,
                                         Qt.AspectRatioMode.KeepAspectRatio,
                                         Qt.TransformationMode.SmoothTransformation)
            qr_x = x0 + (avail_w - scaled_qr.width()) // 2
            qr_y = y + (remaining_h - scaled_qr.height()) // 2
            painter.drawPixmap(qr_x, qr_y, scaled_qr)

            painter.end()

        dialog = QPrintPreviewDialog(printer, self)
        dialog.setWindowTitle("พรีวิว ป้ายเครื่องจักร (A5)")
        dialog.setMinimumSize(800, 600)
        dialog.paintRequested.connect(paint_label)
        dialog.exec()





# ─── Intake Form Dialog ─────────────────────────────────────
class IntakeFormDialog(QDialog):
    """4-section tabbed dialog for creating a machine intake form."""

    def __init__(self, parent=None, form=None, readonly=False):
        super().__init__(parent)
        self.setWindowTitle("ใบรับเครื่องจักรใหม่" if not form else f"ใบรับ {form.form_number}")
        self.setMinimumSize(680, 600)
        self.setStyleSheet(f"QDialog {{ background: {BG_PANEL}; }}")
        self._form = form        # existing form for editing
        self._readonly = readonly
        self._manual_path    = form.manual_file_path   if form else None
        self._training_path  = form.training_file_path if form else None
        self._build_ui()
        if form:
            self._populate(form)

    def _lbl(self, txt):
        l = QLabel(txt)
        l.setStyleSheet(f"color:{TEXT_MUTED}; background:transparent; font-size:12px;")
        return l

    def _field(self, placeholder="", val=""):
        w = QLineEdit()
        w.setPlaceholderText(placeholder)
        w.setText(str(val) if val else "")
        w.setReadOnly(self._readonly)
        return w

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # Header bar
        hdr = QWidget()
        hdr.setFixedHeight(56)
        hdr.setStyleSheet(f"background:{BG_CARD}; border-bottom:1px solid {BORDER};")
        hl = QHBoxLayout(hdr)
        hl.setContentsMargins(20, 0, 20, 0)
        t = QLabel("📋  ใบรับเครื่องจักร")
        t.setFont(QFont("Segoe UI", 14, QFont.Weight.Bold))
        t.setStyleSheet(f"color:{TEXT_PRIMARY}; background:transparent;")
        hl.addWidget(t)
        
        self.reject_banner = QLabel()
        self.reject_banner.setStyleSheet(f"color: {RED}; font-weight: bold; background: rgba(255,0,0,0.1); padding: 4px 12px; border-radius: 4px; margin-left: 12px;")
        self.reject_banner.hide()
        hl.addWidget(self.reject_banner)
        
        hl.addStretch()
        root.addWidget(hdr)

        # Tab widget
        self.tabs = QTabWidget()
        self.tabs.setStyleSheet(f"""
            QTabWidget::pane {{ border: none; background: {BG_PANEL}; }}
            QTabBar::tab {{
                background: {BG_CARD}; color: {TEXT_MUTED};
                padding: 8px 20px; border: none;
                border-bottom: 2px solid transparent;
            }}
            QTabBar::tab:selected {{
                background: {BG_PANEL}; color: {ACCENT};
                border-bottom: 2px solid {ACCENT};
            }}
        """)
        root.addWidget(self.tabs, 1)

        self.tabs.addTab(self._tab_basic(),     "1️⃣  ข้อมูลพื้นฐาน")
        self.tabs.addTab(self._tab_specs(),     "2️⃣  สเปคไฟฟ้า")
        self.tabs.addTab(self._tab_supplier(),  "3️⃣  ซัพพลายเออร์")
        self.tabs.addTab(self._tab_checklist(), "4️⃣  Checklist & ไฟล์")

        # Footer buttons
        footer = QWidget()
        footer.setStyleSheet(f"background:{BG_CARD}; border-top:1px solid {BORDER};")
        fl = QHBoxLayout(footer)
        fl.setContentsMargins(20, 10, 20, 10)
        fl.addStretch()

        cancel_btn = QPushButton("ยกเลิก")
        cancel_btn.setObjectName("btn_secondary")
        cancel_btn.clicked.connect(self.reject)
        fl.addWidget(cancel_btn)

        if not self._readonly:
            self.save_btn = QPushButton("💾  บันทึก Draft")
            self.save_btn.setObjectName("btn_secondary")
            self.save_btn.clicked.connect(lambda: self.done(1))
            fl.addWidget(self.save_btn)

            self.print_btn = QPushButton("🖨  ปริ้นใบรับ")
            self.print_btn.setObjectName("btn_secondary")
            self.print_btn.clicked.connect(self._print_form)
            fl.addWidget(self.print_btn)

            self.submit_btn = QPushButton("📨  ส่งขออนุมัติ")
            self.submit_btn.setObjectName("btn_secondary")
            self.submit_btn.clicked.connect(lambda: self.done(2))
            fl.addWidget(self.submit_btn)

        root.addWidget(footer)

    def _scrollable(self):
        from PyQt6.QtWidgets import QScrollArea
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        inner = QWidget()
        scroll.setWidget(inner)
        lay = QVBoxLayout(inner)
        lay.setContentsMargins(24, 20, 24, 20)
        lay.setSpacing(10)
        return scroll, lay

    def _tab_basic(self):
        scroll, lay = self._scrollable()
        form = QFormLayout()
        form.setSpacing(10)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)

        self.f_code   = self._field("ST-001", "")
        self.f_name   = self._field("ชื่อเครื่องจักร")
        self.f_model  = self._field("Model / ยี่ห้อ")
        self.f_serial = self._field("S/N ...")
        self.f_zone   = self._field("เช่น STOCK FG, บำบัดน้ำเสีย")

        from PyQt6.QtWidgets import QDateEdit
        from PyQt6.QtCore import QDate, QLocale
        self.f_inst_date = QDateEdit()
        self.f_inst_date.setCalendarPopup(True)
        self.f_inst_date.setDate(QDate.currentDate())
        self.f_inst_date.setReadOnly(self._readonly)
        self.f_inst_date.setLocale(QLocale(QLocale.Language.English, QLocale.Country.UnitedStates))
        self.f_inst_date.setDisplayFormat("dd/MM/yyyy")

        for lbl, w in [
            ("รหัสเครื่องจักร *", self.f_code),
            ("ชื่อเครื่องจักร *",  self.f_name),
            ("รุ่น / ยี่ห้อ",       self.f_model),
            ("Serial Number",       self.f_serial),
            ("โซน (Zone)",          self.f_zone),
            ("วันที่รับเครื่อง",     self.f_inst_date),
        ]:
            form.addRow(self._lbl(lbl), w)

        lay.addLayout(form)
        lay.addStretch()
        return scroll

    def _tab_specs(self):
        scroll, lay = self._scrollable()
        form = QFormLayout()
        form.setSpacing(10)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)

        self.f_power   = self._field("kW")
        self.f_voltage = self._field("V")
        self.f_current = self._field("A")
        self.f_dims    = self._field("กxยxส mm")
        self.f_weight  = self._field("kg")

        from PyQt6.QtWidgets import QComboBox
        self.f_phase = QComboBox()
        self.f_phase.addItems(["3 เฟส (Three Phase)", "1 เฟส (Single Phase)"])
        self.f_phase.setEnabled(not self._readonly)

        for lbl, w in [
            ("กำลังไฟ (kW)",   self.f_power),
            ("แรงดัน (V)",      self.f_voltage),
            ("กระแสไฟ (A)",    self.f_current),
            ("เฟส",             self.f_phase),
            ("ขนาด (กxยxส)",   self.f_dims),
            ("น้ำหนัก (kg)",    self.f_weight),
        ]:
            form.addRow(self._lbl(lbl), w)

        lay.addLayout(form)
        lay.addStretch()
        return scroll

    def _tab_supplier(self):
        scroll, lay = self._scrollable()
        form = QFormLayout()
        form.setSpacing(10)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)

        self.f_sup_name    = self._field("บริษัท / ร้านค้า")
        self.f_sup_contact = self._field("เบอร์โทรศัพท์")
        self.f_sup_sales   = self._field("ชื่อพนักงานขาย (เซลล์)")
        self.f_warranty    = self._field("จำนวนเดือน")

        for lbl, w in [
            ("ชื่อซัพพลายเออร์", self.f_sup_name),
            ("เบอร์ติดต่อ",       self.f_sup_contact),
            ("ชื่อเซลล์",         self.f_sup_sales),
            ("ประกัน (เดือน)",    self.f_warranty),
        ]:
            form.addRow(self._lbl(lbl), w)

        lay.addLayout(form)
        lay.addStretch()
        return scroll

    def _tab_checklist(self):
        from PyQt6.QtWidgets import QCheckBox, QTextEdit
        scroll, lay = self._scrollable()

        def chk(label, checked=False):
            cb = QCheckBox(label)
            cb.setChecked(checked)
            cb.setEnabled(not self._readonly)
            cb.setStyleSheet(f"color:{TEXT_PRIMARY}; font-size:13px;")
            return cb

        # Safety
        safety_grp = QFrame()
        safety_grp.setObjectName("card")
        sg = QVBoxLayout(safety_grp)
        sg.setContentsMargins(14, 12, 14, 12)
        sg.setSpacing(6)
        sg.addWidget(make_label("🛡  ความปลอดภัย", 13, bold=True))
        self.cb_safety = chk("อุปกรณ์ความปลอดภัยครบถ้วน (Safety guards, Emergency stop, ฯลฯ)")
        sg.addWidget(self.cb_safety)
        self.f_safety_notes = QTextEdit()
        self.f_safety_notes.setPlaceholderText("หมายเหตุด้านความปลอดภัย...")
        self.f_safety_notes.setFixedHeight(56)
        self.f_safety_notes.setReadOnly(self._readonly)
        sg.addWidget(self.f_safety_notes)
        lay.addWidget(safety_grp)

        # Spare parts
        spare_grp = QFrame()
        spare_grp.setObjectName("card")
        sp = QVBoxLayout(spare_grp)
        sp.setContentsMargins(14, 12, 14, 12)
        sp.setSpacing(6)
        sp.addWidget(make_label("🔩  อะไหล่ (Spare Parts)", 13, bold=True))
        self.cb_spare = chk("อะไหล่สำรองเบื้องต้นครบถ้วน")
        sp.addWidget(self.cb_spare)
        self.f_spare_notes = QTextEdit()
        self.f_spare_notes.setPlaceholderText("รายการอะไหล่ที่ได้รับ...")
        self.f_spare_notes.setFixedHeight(56)
        self.f_spare_notes.setReadOnly(self._readonly)
        sp.addWidget(self.f_spare_notes)
        lay.addWidget(spare_grp)

        # Manual
        manual_grp = QFrame()
        manual_grp.setObjectName("card")
        mg = QVBoxLayout(manual_grp)
        mg.setContentsMargins(14, 12, 14, 12)
        mg.setSpacing(6)
        mg.addWidget(make_label("📖  คู่มือเครื่องจักร", 13, bold=True))
        self.cb_manual = chk("มีคู่มือเครื่องจักร (Manual)")
        mg.addWidget(self.cb_manual)

        manual_row = QHBoxLayout()
        self.manual_lbl = QPushButton("ยังไม่มีไฟล์คู่มือ")
        self.manual_lbl.setStyleSheet(f"color:{BLUE}; font-size:12px; font-weight:bold; background:transparent; border:none; text-align:left;")
        self.manual_lbl.setCursor(Qt.CursorShape.PointingHandCursor)
        self.manual_lbl.clicked.connect(lambda: self._open_file(self._manual_path))
        manual_row.addWidget(self.manual_lbl)
        if not self._readonly:
            pick_manual = QPushButton("📎  เลือก PDF คู่มือ")
            pick_manual.setObjectName("btn_small")
            pick_manual.clicked.connect(self._pick_manual)
            manual_row.addWidget(pick_manual)
        mg.addLayout(manual_row)
        lay.addWidget(manual_grp)

        # Training
        train_grp = QFrame()
        train_grp.setObjectName("card")
        tg = QVBoxLayout(train_grp)
        tg.setContentsMargins(14, 12, 14, 12)
        tg.setSpacing(6)
        tg.addWidget(make_label("🎓  การอบรมการใช้งาน", 13, bold=True))
        self.cb_training = chk("ผ่านการอบรมการใช้งานแล้ว")
        tg.addWidget(self.cb_training)
        train_row = QHBoxLayout()
        self.train_lbl = QPushButton("ยังไม่มีไฟล์เอกสารอบรม")
        self.train_lbl.setStyleSheet(f"color:{BLUE}; font-size:12px; font-weight:bold; background:transparent; border:none; text-align:left;")
        self.train_lbl.setCursor(Qt.CursorShape.PointingHandCursor)
        self.train_lbl.clicked.connect(lambda: self._open_file(self._training_path))
        train_row.addWidget(self.train_lbl)
        if not self._readonly:
            pick_train = QPushButton("📎  เลือกเอกสารอบรม")
            pick_train.setObjectName("btn_small")
            pick_train.clicked.connect(self._pick_training)
            train_row.addWidget(pick_train)
        tg.addLayout(train_row)

        self.f_train_notes = QTextEdit()
        self.f_train_notes.setPlaceholderText("หมายเหตุการอบรม...")
        self.f_train_notes.setFixedHeight(48)
        self.f_train_notes.setReadOnly(self._readonly)
        tg.addWidget(self.f_train_notes)
        lay.addWidget(train_grp)

        # Signed Form
        self._signed_path = getattr(self, '_signed_path', None)
        signed_grp = QFrame()
        signed_grp.setObjectName("card")
        sg = QVBoxLayout(signed_grp)
        sg.setContentsMargins(14, 12, 14, 12)
        sg.setSpacing(6)
        sg.addWidget(make_label("✍  ไฟล์เซ็นตรวจสอบหน้างาน (Signed Form)", 13, bold=True))
        signed_row = QHBoxLayout()
        self.signed_lbl = QPushButton("ยังไม่ได้แนบใบเซ็น")
        self.signed_lbl.setStyleSheet(f"color:{BLUE}; font-size:12px; font-weight:bold; background:transparent; border:none; text-align:left;")
        self.signed_lbl.setCursor(Qt.CursorShape.PointingHandCursor)
        self.signed_lbl.clicked.connect(lambda: self._open_file(self._signed_path))
        signed_row.addWidget(self.signed_lbl)
        if not self._readonly:
            pick_signed = QPushButton("📎  แนบใบเซ็นสแกน")
            pick_signed.setObjectName("btn_small")
            pick_signed.clicked.connect(self._pick_signed)
            signed_row.addWidget(pick_signed)
        sg.addLayout(signed_row)
        lay.addWidget(signed_grp)

        lay.addStretch()
        return scroll

    def _open_file(self, path):
        if not path: return
        import os
        try:
            if os.name == 'nt':
                os.startfile(path)
            else:
                import subprocess
                subprocess.call(('open' if sys.platform == 'darwin' else 'xdg-open', path))
        except Exception as e:
            QMessageBox.warning(self, "เปิดไฟล์ไม่ได้", f"ไม่สามารถเปิดไฟล์ได้:\n{str(e)}")

    def _pick_manual(self):
        from PyQt6.QtWidgets import QFileDialog
        p, _ = QFileDialog.getOpenFileName(self, "เลือกไฟล์คู่มือ", "", "PDF Files (*.pdf);;All Files (*)")
        if p:
            self._manual_path = p
            import os
            self.manual_lbl.setText(f"✅  {os.path.basename(p)}")

    def _pick_training(self):
        from PyQt6.QtWidgets import QFileDialog
        p, _ = QFileDialog.getOpenFileName(self, "เลือกเอกสารอบรม", "", "PDF Files (*.pdf);;All Files (*)")
        if p:
            self._training_path = p
            import os
            self.train_lbl.setText(f"✅  {os.path.basename(p)}")

    def _pick_signed(self):
        from PyQt6.QtWidgets import QFileDialog
        p, _ = QFileDialog.getOpenFileName(self, "เลือกใบเซ็นสแกน", "", "PDF Files (*.pdf);;Images (*.png *.jpg *.jpeg);;All Files (*)")
        if p:
            self._signed_path = p
            import os
            self.signed_lbl.setText(f"✅  {os.path.basename(p)}")

    def _print_form(self):
        from PyQt6.QtPrintSupport import QPrinter, QPrintPreviewDialog
        from PyQt6.QtGui import QTextDocument, QPageSize
        from services import SettingsService

        import os
        def _fname(path):
            return f" (แนบไฟล์: {os.path.basename(path)})" if path else ""

        data = self.collect_data()
        
        logo_path = SettingsService.get_setting("company_logo_path")
        logo_html = ""
        if logo_path and os.path.exists(logo_path):
            # Use height: 0px trick because QTextDocument ignores absolute positioning for text overlap.
            logo_html = f'<div style="opacity: 0.15; height: 0px; text-align: left; margin-top: -20px; margin-left: -10px;"><img src="file:///{logo_path.replace(chr(92), "/")}" width="100"></div>'

        # Build HTML for printing without excessive table spacing
        html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: 'TH Sarabun New', 'TH SarabunPSK', 'Sarabun', 'Segoe UI', sans-serif; font-size: 11pt; margin: 30px; color: #000; line-height: 1.4; }}
                h1 {{ text-align: center; color: #000; border-bottom: 2px solid #000; padding-bottom: 5px; font-size: 22pt; font-weight: bold; margin-bottom: 15px; margin-top: 5px; }}
                h3 {{ color: #000; margin-top: 15px; font-size: 13pt; font-weight: bold; margin-bottom: 6px; }}
                .data-table {{ width: 100%; border-collapse: collapse; margin-bottom: 12px; }}
                .data-table th, .data-table td {{ border: 1px solid #333; padding: 6px; text-align: center; vertical-align: middle; word-wrap: break-word; }}
                .data-table th {{ background-color: #f5f5f5; font-weight: bold; }}
                .item {{ margin-bottom: 4px; }}
                .label {{ font-weight: bold; width: 140px; display: inline-block; }}
                .signatures {{ margin-top: 30px; width: 100%; text-align: center; }}
                .signatures td {{ padding-top: 30px; font-size: 11pt; border: none; }}
                .sign-line {{ border-top: 1px dashed #333; width: 80%; margin: 0 auto; margin-top: 30px; padding-top: 5px; }}
            </style>
        </head>
        <body>
            {logo_html}
            <div style="max-width: 800px; margin: 0 auto; padding-top: 20px;">
                <h1>ใบรับเครื่องจักร (Machine Intake Form)</h1>
                
                <h3>1. ข้อมูลพื้นฐาน</h3>
                <table class="data-table">
                    <tr>
                        <th>รหัสเครื่องจักร</th>
                        <th>ชื่อเครื่องจักร</th>
                        <th>รุ่น / ยี่ห้อ</th>
                        <th>Serial Number</th>
                        <th>วันที่รับเครื่อง</th>
                        <th>โซน</th>
                    </tr>
                    <tr>
                        <td>{data.get('code', '-')}</td>
                        <td>{data.get('name', '-')}</td>
                        <td>{data.get('model', '-')}</td>
                        <td>{data.get('serial_number', '-')}</td>
                        <td>{data.get('installation_date').strftime('%d/%m/%Y') if data.get('installation_date') else '-'}</td>
                        <td>{data.get('zone', '-')}</td>
                    </tr>
                </table>

                <h3>2. สเปคไฟฟ้าและขนาด</h3>
                <table class="data-table">
                    <tr>
                        <th>กำลังไฟ (kW)</th>
                        <th>น้ำหนัก (kg)</th>
                        <th>แรงดัน (V)</th>
                        <th>กระแส (A)</th>
                        <th>เฟส</th>
                        <th>ขนาด (กxยxส)</th>
                    </tr>
                    <tr>
                        <td>{data.get('power_kw') or '-'}</td>
                        <td>{data.get('weight_kg') or '-'}</td>
                        <td>{data.get('voltage_v') or '-'}</td>
                        <td>{data.get('current_amp') or '-'}</td>
                        <td>{data.get('phase', '-')} เฟส</td>
                        <td>{data.get('dimensions', '-')}</td>
                    </tr>
                </table>

                <h3>3. ซัพพลายเออร์</h3>
                <table class="data-table">
                    <tr>
                        <th>ชื่อบริษัท</th>
                        <th>เบอร์ติดต่อ</th>
                        <th>ชื่อเซลล์</th>
                        <th>ระยะประกัน (เดือน)</th>
                    </tr>
                    <tr>
                        <td>{data.get('supplier_name') or '-'}</td>
                        <td>{data.get('supplier_contact') or '-'}</td>
                        <td>{data.get('supplier_sales') or '-'}</td>
                        <td>{data.get('warranty_months') or '-'}</td>
                    </tr>
                </table>

                <h3>4. Checklist ตรวจรับ</h3>
                <div class="item"><span class="label">ความปลอดภัย:</span> {'☑ ผ่าน' if data.get('safety_checked') else '☐ ไม่ผ่าน'} {f"({data.get('safety_notes')})" if data.get('safety_notes') else ''}</div>
                <div class="item"><span class="label">อะไหล่สำรอง:</span> {'☑ ครบ' if data.get('spare_parts_checked') else '☐ ไม่ครบ'} {f"({data.get('spare_parts_notes')})" if data.get('spare_parts_notes') else ''}</div>
                <div class="item"><span class="label">คู่มือเครื่องจักร:</span> {'☑ มี' if data.get('has_manual') else '☐ ไม่มี'} {_fname(data.get('manual_file_path'))}</div>
                <div class="item"><span class="label">การอบรมการใช้งาน:</span> {'☑ อบรมแล้ว' if data.get('training_done') else '☐ ยังไม่อบรม'} {f"({data.get('training_notes')})" if data.get('training_notes') else ''} {_fname(data.get('training_file_path'))}</div>

                <table class="signatures">
                    <tr>
                        <td style="width: 50%;">
                            <div class="sign-line">ลงชื่อผู้ตรวจสอบ (ช่าง)</div>
                            <div style="margin-top:5px;">(......................................................)</div>
                            <div style="margin-top:5px;">วันที่:......./......./.......</div>
                        </td>
                        <td style="width: 50%;">
                            <div class="sign-line">ลงชื่อผู้อนุมัติ (Manager/Admin)</div>
                            <div style="margin-top:5px;">(......................................................)</div>
                            <div style="margin-top:5px;">วันที่:......./......./.......</div>
                        </td>
                    </tr>
                </table>
            </div>
        </body>
        </html>
        """

        from PyQt6.QtGui import QTextDocument, QPageSize
        doc = QTextDocument()
        doc.setHtml(html)

        printer = QPrinter(QPrinter.PrinterMode.ScreenResolution)
        printer.setPageSize(QPageSize(QPageSize.PageSizeId.A4))

        preview = QPrintPreviewDialog(printer, self)
        preview.setWindowTitle("ตัวอย่างก่อนพิมพ์ - ใบรับเครื่องจักร")
        # Ensure preview opens in a reasonable size
        preview.resize(1000, 800)
        preview.paintRequested.connect(doc.print)
        preview.exec()

    def _populate(self, form):
        """Fill all fields from an existing form object."""
        if form.status == "Rejected" and form.reject_reason:
            self.reject_banner.setText(f"❌ ถูกปฏิเสธ: {form.reject_reason}")
            self.reject_banner.show()
            
        self.f_code.setText(form.code or "")
        self.f_name.setText(form.name or "")
        self.f_model.setText(form.model or "")
        self.f_serial.setText(form.serial_number or "")
        self.f_zone.setText(form.zone or "")
        if form.power_kw:   self.f_power.setText(str(form.power_kw))
        if form.voltage_v:  self.f_voltage.setText(str(form.voltage_v))
        if form.current_amp: self.f_current.setText(str(form.current_amp))
        if form.phase == 1: self.f_phase.setCurrentIndex(1)
        if form.dimensions:  self.f_dims.setText(form.dimensions)
        if form.weight_kg:   self.f_weight.setText(str(form.weight_kg))
        self.f_sup_name.setText(form.supplier_name or "")
        self.f_sup_contact.setText(form.supplier_contact or "")
        self.f_sup_sales.setText(form.supplier_sales or "")
        if form.warranty_months: self.f_warranty.setText(str(form.warranty_months))
        self.cb_safety.setChecked(bool(form.safety_checked))
        self.f_safety_notes.setPlainText(form.safety_notes or "")
        self.cb_spare.setChecked(bool(form.spare_parts_checked))
        self.f_spare_notes.setPlainText(form.spare_parts_notes or "")
        self.cb_manual.setChecked(bool(form.has_manual))
        if form.manual_file_path:
            import os
            self.manual_lbl.setText(f"✅  {os.path.basename(form.manual_file_path)}")
        self.cb_training.setChecked(bool(form.training_done))
        if form.training_file_path:
            import os
            self.train_lbl.setText(f"✅  {os.path.basename(form.training_file_path)}")
            self._training_path = form.training_file_path
        self.f_train_notes.setPlainText(form.training_notes or "")

        if hasattr(form, 'signed_form_path') and form.signed_form_path:
            import os
            self.signed_lbl.setText(f"✅  {os.path.basename(form.signed_form_path)}")
            self._signed_path = form.signed_form_path

    def collect_data(self) -> dict:
        """Collect all form field values into a dict."""
        from PyQt6.QtCore import QDate
        inst = self.f_inst_date.date()
        import datetime as dt

        def _float(w):
            try: return float(w.text())
            except: return None

        def _int(w):
            try: return int(w.text())
            except: return None

        return {
            "code":             self.f_code.text().strip(),
            "name":             self.f_name.text().strip(),
            "model":            self.f_model.text().strip(),
            "serial_number":    self.f_serial.text().strip(),
            "zone":             self.f_zone.text().strip(),
            "installation_date": dt.datetime(inst.year(), inst.month(), inst.day()),
            "power_kw":         _float(self.f_power),
            "voltage_v":        _float(self.f_voltage),
            "current_amp":      _float(self.f_current),
            "phase":            1 if self.f_phase.currentIndex() == 1 else 3,
            "dimensions":       self.f_dims.text().strip(),
            "weight_kg":        _float(self.f_weight),
            "supplier_name":    self.f_sup_name.text().strip(),
            "supplier_contact": self.f_sup_contact.text().strip(),
            "supplier_sales":   self.f_sup_sales.text().strip(),
            "warranty_months":  _int(self.f_warranty),
            "safety_checked":   self.cb_safety.isChecked(),
            "safety_notes":     self.f_safety_notes.toPlainText(),
            "spare_parts_checked": self.cb_spare.isChecked(),
            "spare_parts_notes": self.f_spare_notes.toPlainText(),
            "has_manual":       self.cb_manual.isChecked(),
            "manual_file_path": self._manual_path,
            "training_done":    self.cb_training.isChecked(),
            "training_file_path": getattr(self, '_training_path', None),
            "training_notes":   self.f_train_notes.toPlainText(),
            "signed_form_path": getattr(self, '_signed_path', None),
        }


# ─── Machine Registry Page (3-tab) ──────────────────────────
class MachineRegistryPage(QWidget):
    def __init__(self, current_user=None):
        super().__init__()
        self.current_user = current_user
        self.svc  = MachineService()
        self.isvc = IntakeFormService()
        if self.current_user:
            self.svc.set_current_user(self.current_user)
            self.isvc.set_current_user(self.current_user)
        self._build_ui()
        self.refresh()

    def set_user(self, user):
        self.current_user = user
        self.refresh()

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # ── Tabs ────────────────────────────────────────────────
        self.tabs = QTabWidget()
        self.tabs.setStyleSheet(f"""
            QTabWidget::pane {{ border:none; background:{BG_PANEL}; padding:0; }}
            QTabBar::tab {{
                background:{BG_DARK}; color:{TEXT_MUTED};
                padding:12px 24px; font-size:13px; border:none;
                border-bottom: 3px solid transparent;
                margin-right: 2px;
            }}
            QTabBar::tab:selected {{
                color:{ACCENT}; border-bottom:3px solid {ACCENT};
                background:{BG_PANEL}; font-weight: bold;
            }}
            QTabBar::tab:hover {{
                background:{BG_CARD};
            }}
        """)
        root.addWidget(self.tabs)

        self.tabs.addTab(self._tab_registry(), "📋  ทะเบียนเครื่องจักร")
        self.tabs.addTab(self._tab_pending(),  "⏳  รออนุมัติ")
        self.tabs.addTab(self._tab_new_form(), "➕  ยื่นใบรับเครื่องจักร")
        self.tabs.currentChanged.connect(self.refresh)

    # ── Tab 1: Machine Registry ──────────────────────────────────
    def _tab_registry(self):
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(24, 16, 24, 16)
        lay.setSpacing(12)

        # top bar
        top = QHBoxLayout()
        top.addWidget(make_label("ทะเบียนเครื่องจักร", 17, bold=True))
        top.addStretch()
        self.reg_search = QLineEdit()
        self.reg_search.setPlaceholderText("🔍  ค้นหา...")
        self.reg_search.setFixedWidth(220)
        self.reg_search.textChanged.connect(self._filter_registry)
        top.addWidget(self.reg_search)
        lay.addLayout(top)

        # stat cards
        self.stat_row = QHBoxLayout()
        lay.addLayout(self.stat_row)

        # machine table
        self.reg_table = QTableWidget()
        self.reg_table.verticalHeader().setDefaultSectionSize(40)
        self.reg_table.setColumnCount(8)
        self.reg_table.setHorizontalHeaderLabels(
            ["รหัส", "ชื่อเครื่องจักร", "รุ่น", "เฟส", "ซัพพลายเออร์", "โซน", "สถานะ", "จัดการ"])
        self.reg_table.setAlternatingRowColors(True)
        self.reg_table.setShowGrid(False)
        self.reg_table.verticalHeader().setVisible(False)
        self.reg_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        hdr = self.reg_table.horizontalHeader()
        hdr.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        hdr.setSectionResizeMode(7, QHeaderView.ResizeMode.Fixed)
        self.reg_table.setColumnWidth(7, 180)
        lay.addWidget(self.reg_table)
        return w

    # ── Tab 2: Pending Approvals ─────────────────────────────────
    def _tab_pending(self):
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(24, 16, 24, 16)
        lay.setSpacing(12)

        top = QHBoxLayout()
        top.addWidget(make_label("รออนุมัติ", 17, bold=True))
        top.addStretch()
        refresh_btn = QPushButton("🔄  รีเฟรช")
        refresh_btn.setObjectName("btn_secondary")
        refresh_btn.clicked.connect(self.refresh)
        top.addWidget(refresh_btn)
        lay.addLayout(top)

        self.pending_table = QTableWidget()
        self.pending_table.verticalHeader().setDefaultSectionSize(40)
        self.pending_table.setColumnCount(6)
        self.pending_table.setHorizontalHeaderLabels(
            ["เลขที่ใบรับ", "รหัสเครื่อง", "ชื่อเครื่องจักร", "ผู้ส่ง", "วันที่ส่ง", "จัดการ"])
        self.pending_table.setAlternatingRowColors(True)
        self.pending_table.setShowGrid(False)
        self.pending_table.verticalHeader().setVisible(False)
        self.pending_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        hdr2 = self.pending_table.horizontalHeader()
        hdr2.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        self.pending_table.setColumnWidth(3, 100)
        self.pending_table.setColumnWidth(5, 260)
        lay.addWidget(self.pending_table)
        return w

    # ── Tab 3: New Intake Form ───────────────────────────────────
    def _tab_new_form(self):
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(24, 16, 24, 16)
        lay.setSpacing(12)

        top = QHBoxLayout()
        top.addWidget(make_label("ใบรับเครื่องจักร (Draft)", 17, bold=True))
        top.addStretch()
        new_btn = QPushButton("➕  สร้างใบรับใหม่")
        new_btn.setObjectName("btn_secondary")
        new_btn.clicked.connect(self._open_new_form)
        top.addWidget(new_btn)
        lay.addLayout(top)

        hint = QLabel("รายการใบรับที่ยังไม่ส่ง (Draft) หรือถูกปฏิเสธ (Rejected)")
        hint.setStyleSheet(f"color:{TEXT_MUTED}; font-size:11px; background:transparent;")
        lay.addWidget(hint)

        self.draft_table = QTableWidget()
        self.draft_table.setColumnCount(5)
        self.draft_table.setHorizontalHeaderLabels(
            ["เลขที่", "รหัสเครื่อง", "ชื่อเครื่องจักร", "สถานะ", "จัดการ"])
        self.draft_table.setAlternatingRowColors(True)
        self.draft_table.setShowGrid(False)
        self.draft_table.verticalHeader().setVisible(False)
        self.draft_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        hdr3 = self.draft_table.horizontalHeader()
        hdr3.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        hdr3.setSectionResizeMode(4, QHeaderView.ResizeMode.Fixed)
        self.draft_table.setColumnWidth(4, 260)
        lay.addWidget(self.draft_table)
        return w

    # ── Refresh / Load Data ──────────────────────────────────────
    def refresh(self, *_):
        self._load_registry()
        self._load_pending()
        self._load_drafts()

    def _load_registry(self):
        machines = self.svc.get_all_machines()
        self._all_machines = machines
        self._populate_registry(machines)

        # Stat cards
        while self.stat_row.count():
            it = self.stat_row.takeAt(0)
            if it.widget(): it.widget().deleteLater()
        total   = len(machines)
        running = sum(1 for m in machines if m.status == "Running")
        warning = sum(1 for m in machines if m.status == "Warning")
        broken  = sum(1 for m in machines if m.status == "Breakdown")
        for title, val, color in [
            ("เครื่องจักรทั้งหมด", str(total),   BLUE),
            ("ทำงานปกติ",          str(running), ACCENT_LIGHT),
            ("แจ้งเตือน",          str(warning), YELLOW),
            ("ขัดข้อง",            str(broken),  RED),
        ]:
            card = QFrame(); card.setObjectName("card"); card.setFixedHeight(72)
            cl = QVBoxLayout(card); cl.setContentsMargins(14, 8, 14, 8)
            cl.addWidget(make_label(val, 20, bold=True, color=color))
            cl.addWidget(make_label(title, 11, color=TEXT_MUTED))
            self.stat_row.addWidget(card)

    def _populate_registry(self, machines):
        t = self.reg_table
        t.setRowCount(0)
        is_admin = self.current_user and self.current_user.role == ROLE_ADMIN

        for m in machines:
            row = t.rowCount(); t.insertRow(row); t.setRowHeight(row, 42)
            phase_str = f"{m.phase or 3}φ"
            for col, val in enumerate([m.code, m.name, m.model or "–",
                                        phase_str, m.supplier_name or "–", m.zone or "–"]):
                item = QTableWidgetItem(str(val))
                item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                t.setItem(row, col, item)

            # Status badge
            sc = {"Running": ACCENT_LIGHT, "Warning": YELLOW, "Breakdown": RED}.get(m.status, TEXT_MUTED)
            sl = QLabel(f"  {m.status or 'Running'}  ")
            sl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            sl.setStyleSheet(f"color:{sc}; border:1px solid {sc}; border-radius:10px; font-size:11px; background:transparent;")
            t.setCellWidget(row, 6, self._wrap(sl))

            # Action buttons
            aw = QWidget(); al = QHBoxLayout(aw)
            al.setContentsMargins(4, 2, 4, 2); al.setSpacing(4)
            view_btn = QPushButton("👁 ดู")
            view_btn.setObjectName("btn_small"); view_btn.setFixedHeight(26)
            view_btn.clicked.connect(lambda _, mid=m.id: self._view_machine(mid))
            al.addWidget(view_btn)
            if is_admin:
                edit_btn = QPushButton("✏ แก้ไข")
                edit_btn.setObjectName("btn_small"); edit_btn.setFixedHeight(26)
                edit_btn.clicked.connect(lambda _, mid=m.id: self._edit_machine(mid))
                del_btn = QPushButton("🗑")
                del_btn.setObjectName("btn_danger"); del_btn.setFixedSize(28, 26)
                del_btn.clicked.connect(lambda _, mid=m.id: self._delete_machine(mid))
                al.addWidget(edit_btn); al.addWidget(del_btn)
            al.addStretch()
            t.setCellWidget(row, 7, aw)

    def _load_pending(self):
        forms = self.isvc.get_pending_forms()
        t = self.pending_table
        t.setRowCount(0)

        role = self.current_user.role if self.current_user else ROLE_VIEWER
        can_approve = role in {ROLE_ADMIN, ROLE_MANAGER}

        for f in forms:
            row = t.rowCount(); t.insertRow(row); t.setRowHeight(row, 42)
            sub_name = f.submitted_by.full_name or f.submitted_by.username if f.submitted_by else "–"
            sub_date = f.submitted_at.strftime("%d/%m/%Y %H:%M") if f.submitted_at else "–"
            for col, val in enumerate([f.form_number, f.code, f.name, sub_name, sub_date]):
                item = QTableWidgetItem(str(val))
                item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                t.setItem(row, col, item)

            aw = QWidget(); al = QHBoxLayout(aw)
            al.setContentsMargins(0, 0, 0, 0); al.setSpacing(2)
            view_btn = QPushButton("👁 ดู")
            view_btn.setObjectName("btn_small"); view_btn.setFixedHeight(26)
            view_btn.clicked.connect(lambda _, fid=f.id: self._view_form(fid, readonly=True))
            al.addWidget(view_btn)
            from PyQt6.QtWidgets import QSizePolicy
            if can_approve:
                appr_btn = QPushButton("✅ อนุมัติ")
                appr_btn.setObjectName("btn_secondary"); appr_btn.setFixedHeight(28); appr_btn.setMinimumWidth(115)
                appr_btn.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
                appr_btn.clicked.connect(lambda _, fid=f.id: self._approve_form(fid))
                rej_btn  = QPushButton("❌ ปฏิเสธ")
                rej_btn.setObjectName("btn_danger"); rej_btn.setFixedHeight(28); rej_btn.setMinimumWidth(115)
                rej_btn.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
                rej_btn.clicked.connect(lambda _, fid=f.id: self._reject_form(fid))
                al.addWidget(appr_btn); al.addWidget(rej_btn)
            al.addStretch()
            t.setCellWidget(row, 5, aw)

    def _load_drafts(self):
        all_forms = self.isvc.get_all_forms()
        drafts = [f for f in all_forms if f.status in ("Draft", "Rejected")]
        t = self.draft_table
        t.setRowCount(0)
        STATUS_COLOR = {"Draft": TEXT_MUTED, "Rejected": RED}
        STATUS_ICON  = {"Draft": "📝", "Rejected": "❌"}

        for f in drafts:
            row = t.rowCount(); t.insertRow(row); t.setRowHeight(row, 48)
            for col, val in enumerate([f.form_number, f.code, f.name]):
                item = QTableWidgetItem(str(val))
                item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                t.setItem(row, col, item)

            sc = STATUS_COLOR.get(f.status, TEXT_MUTED)
            si = STATUS_ICON.get(f.status, "")
            sl = QLabel(f"  {si} {f.status}  ")
            if f.status == "Rejected" and f.reject_reason:
                sl.setToolTip(f"เหตุผลที่ปฏิเสธ:\n{f.reject_reason}")
            sl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            sl.setStyleSheet(f"color:{sc}; border:1px solid {sc}; border-radius:10px; font-size:11px; background:transparent;")
            t.setCellWidget(row, 3, self._wrap(sl))

            aw = QWidget(); al = QHBoxLayout(aw)
            al.setContentsMargins(0, 0, 0, 0); al.setSpacing(2)
            edit_btn = QPushButton("✏ แก้ไข")
            edit_btn.setObjectName("btn_small"); edit_btn.setFixedHeight(26)
            edit_btn.clicked.connect(lambda _, fid=f.id: self._edit_form(fid))
            al.addWidget(edit_btn)

            role = self.current_user.role if self.current_user else ROLE_VIEWER
            if role != ROLE_VIEWER:
                sub_btn = QPushButton("📨 ส่งอนุมัติ")
                sub_btn.setObjectName("btn_secondary"); sub_btn.setFixedHeight(26)
                sub_btn.clicked.connect(lambda _, fid=f.id: self._submit_form(fid))
                al.addWidget(sub_btn)
                
                del_btn = QPushButton("🗑 ลบ")
                del_btn.setObjectName("btn_danger"); del_btn.setFixedHeight(26)
                del_btn.clicked.connect(lambda _, fid=f.id: self._delete_draft_form(fid))
                al.addWidget(del_btn)

            al.addStretch()
            t.setCellWidget(row, 4, aw)

    # ── Actions ──────────────────────────────────────────────────
    def _filter_registry(self, text):
        filtered = [m for m in self._all_machines
                    if text.lower() in m.name.lower() or text.lower() in m.code.lower()]
        self._populate_registry(filtered)

    def _open_new_form(self):
        role = self.current_user.role if self.current_user else ROLE_VIEWER
        if role == ROLE_VIEWER:
            QMessageBox.warning(self, "ไม่มีสิทธิ์", "Viewer ไม่สามารถสร้างใบรับได้")
            return
        dlg = IntakeFormDialog(self)
        result = dlg.exec()
        if result in (1, 2):
            data = dlg.collect_data()
            if not data["code"] or not data["name"]:
                QMessageBox.warning(self, "ข้อมูลไม่ครบ", "กรุณากรอกรหัสและชื่อเครื่องจักร")
                return
            uid = self.current_user.id if self.current_user else None
            try:
                form = self.isvc.create_form(data, submitted_by_id=uid)
                if result == 2:  # submit immediately
                    self.isvc.submit_for_approval(form.id, role)
                    QMessageBox.information(self, "ส่งสำเร็จ",
                        f"ส่งใบรับ {form.form_number} ขออนุมัติเรียบร้อยแล้ว")
                    self.tabs.setCurrentIndex(1)
                else:
                    QMessageBox.information(self, "บันทึกแล้ว",
                        f"บันทึกใบรับ {form.form_number} เป็น Draft")
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def _edit_form(self, form_id):
        form = self.isvc.get_form(form_id)
        dlg = IntakeFormDialog(self, form=form)
        result = dlg.exec()
        if result in (1, 2):
            data = dlg.collect_data()
            role = self.current_user.role if self.current_user else ROLE_VIEWER
            try:
                self.isvc.update_form(form_id, data)
                if result == 2:
                    self.isvc.submit_for_approval(form_id, role)
                    QMessageBox.information(self, "ส่งสำเร็จ", "ส่งขออนุมัติเรียบร้อยแล้ว")
                    self.tabs.setCurrentIndex(1)
                else:
                    QMessageBox.information(self, "บันทึกแล้ว", "อัปเดต Draft สำเร็จ")
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def _submit_form(self, form_id):
        role = self.current_user.role if self.current_user else ROLE_VIEWER
        try:
            form = self.isvc.submit_for_approval(form_id, role)
            QMessageBox.information(self, "ส่งสำเร็จ",
                f"ส่งใบรับ {form.form_number} ขออนุมัติแล้ว")
            self.tabs.setCurrentIndex(1)
            self.refresh()
        except Exception as e:
            QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def _view_form(self, form_id, readonly=False):
        form = self.isvc.get_form(form_id)
        dlg = IntakeFormDialog(self, form=form, readonly=readonly)
        dlg.exec()

    def _approve_form(self, form_id):
        if not self.current_user: return
        reply = QMessageBox.question(self, "อนุมัติ",
            "ต้องการอนุมัติใบรับนี้และลงทะเบียนเครื่องจักรใช่หรือไม่?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply == QMessageBox.StandardButton.Yes:
            try:
                machine = self.isvc.approve_form(
                    form_id, self.current_user.id, self.current_user.role)
                QMessageBox.information(self, "อนุมัติสำเร็จ",
                    f"ลงทะเบียนเครื่องจักร {machine.code} สำเร็จแล้ว")
                self.tabs.setCurrentIndex(0)
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def _reject_form(self, form_id):
        from PyQt6.QtWidgets import QInputDialog
        reason, ok = QInputDialog.getText(self, "ปฏิเสธใบรับ", "เหตุผลที่ปฏิเสธ:")
        if ok:
            try:
                self.isvc.reject_form(form_id, self.current_user.id,
                                      self.current_user.role, reason)
                QMessageBox.information(self, "ปฏิเสธแล้ว", "ปฏิเสธใบรับเรียบร้อยแล้ว")
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def _delete_draft_form(self, form_id):
        reply = QMessageBox.question(self, "ยืนยันการลบ",
            "ต้องการลบใบรับฉบับร่างนี้ใช่หรือไม่?\n(ไม่สามารถกู้คืนได้)",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply == QMessageBox.StandardButton.Yes:
            try:
                self.isvc.delete_form(form_id)
                QMessageBox.information(self, "ลบสำเร็จ", "ลบใบรับเรียบร้อยแล้ว")
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def _view_machine(self, machine_id):
        m = self.svc.get_machine(machine_id)
        if not m: return
        dlg = ViewMachineDialog(m, self)
        dlg.exec()

    def _edit_machine(self, machine_id):
        m = self.svc.get_machine(machine_id)
        if not m: return
        dlg = AddMachineDialog(self)
        dlg.setWindowTitle(f"แก้ไขเครื่องจักร {m.code}")
        dlg.code_input.setText(m.code)
        dlg.name_input.setText(m.name)
        dlg.model_input.setText(m.model or "")
        dlg.serial_input.setText(m.serial_number or "")
        dlg.zone_input.setText(m.zone or "")
        dlg.resp_input.setText(m.responsible_person or "")
        if dlg.exec():
            try:
                self.svc.update_machine(machine_id,
                    code=dlg.code_input.text().strip(),
                    name=dlg.name_input.text().strip(),
                    model=dlg.model_input.text(),
                    serial_number=dlg.serial_input.text(),
                    zone=dlg.zone_input.text(),
                    responsible_person=dlg.resp_input.text())
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def _delete_machine(self, machine_id):
        m = self.svc.get_machine(machine_id)
        if not m: return
        reply = QMessageBox.question(self, "ลบเครื่องจักร",
            f"ต้องการลบเครื่องจักร {m.code} – {m.name} ใช่หรือไม่?\n⚠️ ไม่สามารถกู้คืนได้",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply == QMessageBox.StandardButton.Yes:
            try:
                self.svc.delete_machine(machine_id)
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    @staticmethod
    def _wrap(widget):
        w = QWidget(); l = QHBoxLayout(w)
        l.setContentsMargins(6, 2, 6, 2); l.addWidget(widget)
        return w

    # Legacy methods kept for backward compat
    def load_data(self): self.refresh()
    def gen_qr(self, code):
        try:
            path = self.svc.generate_qr(code)
            QMessageBox.information(self, "สร้าง QR Code", f"บันทึกที่:\n{path}")
        except Exception as e:
            QMessageBox.critical(self, "Error", str(e))

    def attach_file(self, machine_id):
        from PyQt6.QtWidgets import QFileDialog
        path, _ = QFileDialog.getOpenFileName(self, "เลือกไฟล์แนบ", "", "All Files (*)")
        if path:
            try:
                self.svc.add_attachment(machine_id, path, "Document")
                QMessageBox.information(self, "สำเร็จ", "แนบไฟล์เรียบร้อย")
            except Exception as e:
                QMessageBox.critical(self, "Error", str(e))



    def _populate_table(self, machines):
        self.table.setRowCount(0)
        for m in machines:
            row = self.table.rowCount()
            self.table.insertRow(row)
            self.table.setRowHeight(row, 44)

            for col, val in enumerate([
                m.code, m.name, m.model or "–", m.serial_number or "–", m.zone or "–"
            ]):
                item = QTableWidgetItem(val)
                item.setFlags(item.flags() & ~Qt.ItemFlag.ItemIsEditable)
                self.table.setItem(row, col, item)

            # Status badge
            status = m.status or "Running"
            status_color = {
                "Running": ACCENT_LIGHT, "Warning": YELLOW, "Breakdown": RED
            }.get(status, TEXT_MUTED)
            s_lbl = QLabel(f"  {status}  ")
            s_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            s_lbl.setStyleSheet(
                f"color: {status_color}; background: rgba(0,0,0,0.3);"
                f"border: 1px solid {status_color}; border-radius: 10px;"
                f"font-size: 11px; font-weight: 600;"
            )
            self.table.setCellWidget(row, 5, self._wrap(s_lbl))

            # Action buttons
            action_w = QWidget()
            action_l = QHBoxLayout(action_w)
            action_l.setContentsMargins(4, 2, 4, 2)
            action_l.setSpacing(4)

            qr_btn = QPushButton("QR")
            qr_btn.setObjectName("btn_small")
            qr_btn.setFixedSize(38, 28)
            qr_btn.setToolTip("สร้าง QR Code")
            qr_btn.clicked.connect(lambda _, c=m.code: self.gen_qr(c))

            att_btn = QPushButton("📎")
            att_btn.setObjectName("btn_small")
            att_btn.setFixedSize(32, 28)
            att_btn.setToolTip("แนบไฟล์")
            att_btn.clicked.connect(lambda _, mid=m.id: self.attach_file(mid))

            action_l.addWidget(qr_btn)
            action_l.addWidget(att_btn)
            action_l.addStretch()
            self.table.setCellWidget(row, 6, action_w)

    @staticmethod
    def _wrap(widget):
        """Centre-align a widget in a table cell."""
        w = QWidget()
        l = QHBoxLayout(w)
        l.setContentsMargins(6, 2, 6, 2)
        l.addWidget(widget)
        return w

    def filter_table(self, text):
        filtered = [m for m in self._all_machines
                    if text.lower() in m.name.lower() or text.lower() in m.code.lower()]
        self._populate_table(filtered)

    def on_add_machine(self):
        dlg = AddMachineDialog(self)
        if dlg.exec():
            code = dlg.code_input.text().strip()
            name = dlg.name_input.text().strip()
            if not code or not name:
                QMessageBox.warning(self, "ข้อมูลไม่ครบ",
                                    "กรุณากรอกรหัสและชื่อเครื่องจักร")
                return
            try:
                self.service.add_machine(
                    code=code, name=name,
                    model=dlg.model_input.text(),
                    serial_number=dlg.serial_input.text(),
                    installation_date=None,
                    zone=dlg.zone_input.text()
                )
                self.load_data()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def gen_qr(self, code):
        try:
            path = self.service.generate_qr(code)
            QMessageBox.information(self, "สร้าง QR Code สำเร็จ",
                                    f"บันทึกที่:\n{path}")
        except Exception as e:
            QMessageBox.critical(self, "Error", str(e))

    def attach_file(self, machine_id):
        from PyQt6.QtWidgets import QFileDialog
        path, _ = QFileDialog.getOpenFileName(self, "เลือกไฟล์แนบ", "", "All Files (*)")
        if path:
            try:
                self.service.add_attachment(machine_id, path, "Document")
                QMessageBox.information(self, "สำเร็จ", "แนบไฟล์เรียบร้อยแล้ว")
            except Exception as e:
                QMessageBox.critical(self, "Error", str(e))



# ─── Add/Edit User Dialog ──────────────────────────────────────
class AddUserDialog(QDialog):

    def __init__(self, parent=None, user=None):
        super().__init__(parent)
        from PyQt6.QtWidgets import QComboBox
        self._edit_mode = user is not None
        title_txt = "แก้ไขผู้ใช้" if self._edit_mode else "เพิ่มผู้ใช้ใหม่"
        self.setWindowTitle(title_txt)
        self.setMinimumWidth(400)
        self.setStyleSheet(f"QDialog {{ background: {BG_PANEL}; }}")

        root = QVBoxLayout(self)
        root.setContentsMargins(24, 24, 24, 24)
        root.setSpacing(12)

        root.addWidget(make_label(title_txt, 16, bold=True))
        root.addWidget(make_separator())

        form = QFormLayout()
        form.setSpacing(10)
        form.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        lbl_s = f"color:{TEXT_MUTED};background:transparent;"

        self.name_input = QLineEdit(); self.name_input.setPlaceholderText("ชื่อ-นามสกุล")
        self.user_input = QLineEdit(); self.user_input.setPlaceholderText("technician01")
        self.pw_input   = QLineEdit(); self.pw_input.setEchoMode(QLineEdit.EchoMode.Password)
        self.pw_input.setPlaceholderText("รหัสผ่าน")

        self.role_combo = QComboBox()
        self.role_combo.setStyleSheet(
            f"background:{BG_CARD};color:{TEXT_PRIMARY};"
            f"border:1px solid {BORDER};border-radius:6px;padding:6px;"
        )
        for r in ALL_ROLES:
            self.role_combo.addItem(ROLE_META[r]["label"], r)

        for lbl_txt, widget in [
            ("ชื่อเต็ม *",    self.name_input),
            ("ชื่อผู้ใช้ *",   self.user_input),
            ("รหัสผ่าน *",   self.pw_input),
            ("บทบาท *",       self.role_combo),
        ]:
            l = QLabel(lbl_txt); l.setStyleSheet(lbl_s)
            form.addRow(l, widget)

        if self._edit_mode:
            self.name_input.setText(user.full_name or "")
            self.user_input.setText(user.username)
            self.user_input.setReadOnly(True)
            self.user_input.setStyleSheet(
                f"background:{BG_DARK};color:{TEXT_MUTED};"
                f"border:1px solid {BORDER};border-radius:6px;padding:7px;"
            )
            self.pw_input.setPlaceholderText("เว้นว่างเพื่อไม่เปลี่ยน")
            idx = self.role_combo.findData(user.role)
            if idx >= 0:
                self.role_combo.setCurrentIndex(idx)

        root.addLayout(form)
        root.addSpacing(8)
        btn_row = QHBoxLayout()
        btn_row.addStretch()
        cancel = QPushButton("ยกเลิก"); cancel.setObjectName("btn_secondary"); cancel.clicked.connect(self.reject)
        save   = QPushButton("  บันทึก  "); save.setObjectName("btn_primary"); save.clicked.connect(self.accept)
        btn_row.addWidget(cancel); btn_row.addWidget(save)
        root.addLayout(btn_row)


# ─── User Management Page ──────────────────────────────────────
class UserManagementPage(QWidget):
    def __init__(self, current_user=None):
        super().__init__()
        self.current_user = current_user
        self.service = UserService()
        if self.current_user:
            self.service.set_current_user(self.current_user)
        self._all_users = []
        self._build_ui()
        self.load_users()

    def _build_ui(self):
        from PyQt6.QtWidgets import QTabWidget, QComboBox
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 8, 24, 24)
        root.setSpacing(12)

        top = QHBoxLayout()
        top.addWidget(make_label("จัดการผู้ใช้งาน", 18, bold=True))
        top.addStretch()
        add_btn = QPushButton("＋  เพิ่มผู้ใช้")
        add_btn.setObjectName("btn_primary")
        add_btn.clicked.connect(self.on_add_user)
        top.addWidget(add_btn)
        root.addLayout(top)
        root.addWidget(make_separator())

        self.role_cards_row = QHBoxLayout()
        root.addLayout(self.role_cards_row)

        # Tabs
        tabs = QTabWidget()
        tabs.setStyleSheet(f"""
            QTabWidget::pane {{
                border: 1px solid {BORDER};
                background: {BG_PANEL};
                border-radius: 6px;
            }}
            QTabBar::tab {{
                background: {BG_DARK};
                color: {TEXT_MUTED};
                padding: 8px 20px;
                border: none;
            }}
            QTabBar::tab:selected {{
                background: {BG_PANEL};
                color: {TEXT_PRIMARY};
                border-bottom: 2px solid {ACCENT_LIGHT};
                font-weight: 600;
            }}
            QTabBar::tab:hover {{ color: {TEXT_PRIMARY}; }}
        """)

        # ── Tab 1: Users list
        users_tab = QWidget()
        ul = QVBoxLayout(users_tab)
        ul.setContentsMargins(12, 12, 12, 12)
        ul.setSpacing(8)

        search_row = QHBoxLayout()
        self.user_search = QLineEdit()
        self.user_search.setPlaceholderText("🔍  ค้นหาชื่อ...")
        self.user_search.setFixedWidth(240)
        self.user_search.textChanged.connect(self.filter_users)
        search_row.addWidget(self.user_search)
        search_row.addStretch()
        ul.addLayout(search_row)

        self.user_table = QTableWidget()
        self.user_table.verticalHeader().setDefaultSectionSize(40)
        self.user_table.setColumnCount(6)
        self.user_table.setHorizontalHeaderLabels(
            ["ชื่อเต็ม", "ชื่อผู้ใช้", "บทบาท", "สิทธิ์รวม", "สถานะ", "จัดการ"]
        )
        self.user_table.setAlternatingRowColors(True)
        self.user_table.setShowGrid(False)
        self.user_table.verticalHeader().setVisible(False)
        self.user_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        hdr = self.user_table.horizontalHeader()
        hdr.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        hdr.setSectionResizeMode(5, QHeaderView.ResizeMode.Fixed)
        self.user_table.setColumnWidth(5, 200)
        ul.addWidget(self.user_table)
        tabs.addTab(users_tab, "👥  รายชื่อผู้ใช้งาน")

        # ── Tab 2: Permission Matrix
        perm_tab = QWidget()
        pl = QVBoxLayout(perm_tab)
        pl.setContentsMargins(12, 16, 12, 12)
        pl.setSpacing(12)
        pl.addWidget(make_label("ตาราง Permission Matrix — สิทธิ์แต่ละบทบาท", 14, bold=True))
        pl.addWidget(make_separator())
        pl.addWidget(self._build_matrix())
        pl.addStretch()
        tabs.addTab(perm_tab, "🛡  ตารางสิทธิ์")

        root.addWidget(tabs)

    def _build_matrix(self):
        resources = [
            ("machine",     "เครื่องจักร"),
            ("work_order",  "งานแจ้งซ่อม"),
            ("pm_plan",     "แผน PM"),
            ("spare_part",  "คลังอะไหล่"),
            ("work_permit", "ใบอนุญาตงาน"),
            ("user",        "ผู้ใช้งาน"),
            ("audit_log",   "ประวัติดำเนินการ"),
        ]
        actions = ["create", "read", "update", "approve", "delete"]
        ACTION_ICONS = {"create": "＋", "read": "👁", "update": "✎", "approve": "✔", "delete": "🗑"}

        tbl = QTableWidget()
        tbl.setRowCount(len(resources))
        tbl.setColumnCount(len(ALL_ROLES) + 1)
        header_labels = ["ทรัพยากร"] + [ROLE_META[r]["label"].split(" (")[0] for r in ALL_ROLES]
        tbl.setHorizontalHeaderLabels(header_labels)
        tbl.setShowGrid(True)
        tbl.verticalHeader().setVisible(False)
        tbl.setSelectionMode(QTableWidget.SelectionMode.NoSelection)
        tbl.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        tbl.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)

        for r_idx, (res_key, res_label) in enumerate(resources):
            tbl.setRowHeight(r_idx, 80)
            name_item = QTableWidgetItem(res_label)
            name_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
            f = QFont("Segoe UI", 11); f.setBold(True)
            name_item.setFont(f)
            tbl.setItem(r_idx, 0, name_item)

            for c_idx, role in enumerate(ALL_ROLES):
                role_color = ROLE_META[role]["color"]
                perms = PERMISSIONS.get(role, {}).get(res_key, set())
                lines = [f"{ACTION_ICONS[act]} {act}" for act in actions if act in perms]
                cell_text = "\n".join(lines) if lines else "—"
                cell = QTableWidgetItem(cell_text)
                cell.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                cell.setForeground(QColor(role_color if lines else TEXT_MUTED))
                tbl.setItem(r_idx, c_idx + 1, cell)

        container = QWidget()
        cl = QVBoxLayout(container)
        cl.setContentsMargins(0, 0, 0, 0)
        cl.addWidget(tbl)
        return container

    def load_users(self):
        self._all_users = self.service.get_all_users()
        self._update_role_cards()
        self._populate_user_table(self._all_users)

    def _update_role_cards(self):
        while self.role_cards_row.count():
            item = self.role_cards_row.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        from collections import Counter
        counts = Counter(u.role for u in self._all_users)
        for role in ALL_ROLES:
            meta  = ROLE_META[role]
            count = counts.get(role, 0)
            card  = QFrame(); card.setObjectName("card"); card.setFixedHeight(76)
            cl    = QVBoxLayout(card); cl.setContentsMargins(14, 8, 14, 8); cl.setSpacing(2)
            cl.addWidget(make_label(str(count), 22, bold=True, color=meta["color"]))
            cl.addWidget(make_label(meta["label"].split(" (")[0], 11, color=TEXT_MUTED))
            self.role_cards_row.addWidget(card)

    def _populate_user_table(self, users):
        self.user_table.setRowCount(0)
        for u in users:
            row = self.user_table.rowCount()
            self.user_table.insertRow(row)
            self.user_table.setRowHeight(row, 44)

            self.user_table.setItem(row, 0, QTableWidgetItem(u.full_name or "–"))
            self.user_table.setItem(row, 1, QTableWidgetItem(u.username))

            meta = ROLE_META.get(u.role, {"color": TEXT_MUTED, "label": u.role})
            role_lbl = QLabel(f"  {u.role}  ")
            role_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            role_lbl.setStyleSheet(
                f"color:{meta['color']};background:rgba(0,0,0,0.3);"
                f"border:1px solid {meta['color']};border-radius:10px;"
                f"font-size:11px;font-weight:600;"
            )
            self.user_table.setCellWidget(row, 2, self._wrap(role_lbl))

            total = sum(len(v) for v in PERMISSIONS.get(u.role, {}).values())
            perm_item = QTableWidgetItem(f"{total} สิทธิ์รวม")
            perm_item.setForeground(QColor(TEXT_MUTED))
            self.user_table.setItem(row, 3, perm_item)

            active_txt   = "• ใช้งาน" if u.is_active else "• ปิดใช้งาน"
            active_color = ACCENT_LIGHT if u.is_active else RED
            a_lbl = QLabel(active_txt)
            a_lbl.setStyleSheet(f"color:{active_color};background:transparent;font-size:12px;")
            a_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self.user_table.setCellWidget(row, 4, self._wrap(a_lbl))

            aw = QWidget()
            al = QHBoxLayout(aw); al.setContentsMargins(4, 2, 4, 2); al.setSpacing(4)

            def _small(icon, tooltip, fn):
                b = QPushButton(icon); b.setObjectName("btn_small")
                b.setFixedSize(32, 28); b.setToolTip(tooltip); b.clicked.connect(fn)
                return b

            al.addWidget(_small("✎", "แก้ไข",         lambda _, uid=u.id: self.on_edit_user(uid)))
            al.addWidget(_small("🔑", "รีเซ็ตรหัสผ่าน", lambda _, uid=u.id: self.on_reset_pw(uid)))
            al.addWidget(_small("⛔" if u.is_active else "✅", "ปิด/เปิดการใช้งาน",
                                lambda _, uid=u.id, act=u.is_active: self.on_toggle_active(uid, not act)))
            del_btn = QPushButton("🗑"); del_btn.setObjectName("btn_danger")
            del_btn.setFixedSize(32, 28); del_btn.setToolTip("ลบผู้ใช้")
            del_btn.clicked.connect(lambda _, uid=u.id, un=u.username: self.on_delete_user(uid, un))
            al.addWidget(del_btn)
            al.addStretch()
            self.user_table.setCellWidget(row, 5, aw)

    @staticmethod
    def _wrap(w):
        c = QWidget(); l = QHBoxLayout(c)
        l.setContentsMargins(6, 2, 6, 2); l.addWidget(w); return c

    def filter_users(self, text):
        f = [u for u in self._all_users
             if text.lower() in (u.full_name or "").lower()
             or text.lower() in u.username.lower()]
        self._populate_user_table(f)

    def on_add_user(self):
        dlg = AddUserDialog(self)
        if dlg.exec():
            un, fn = dlg.user_input.text().strip(), dlg.name_input.text().strip()
            pw, role = dlg.pw_input.text(), dlg.role_combo.currentData()
            if not un or not fn or not pw:
                QMessageBox.warning(self, "ข้อมูลไม่ครบ", "กรุณากรอกข้อมูลให้ครบถ้วน"); return
            try:
                self.service.create_user(un, pw, role, fn)
                self.load_users()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def on_edit_user(self, user_id):
        user = next((u for u in self._all_users if u.id == user_id), None)
        if not user: return
        dlg = AddUserDialog(self, user=user)
        if dlg.exec():
            try:
                self.service.update_user(user_id,
                    full_name=dlg.name_input.text().strip(),
                    role=dlg.role_combo.currentData())
                if dlg.pw_input.text():
                    self.service.reset_password(user_id, dlg.pw_input.text())
                self.load_users()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def on_reset_pw(self, user_id):
        from PyQt6.QtWidgets import QInputDialog
        new_pw, ok = QInputDialog.getText(
            self, "รีเซ็ตรหัสผ่าน", "กรอกรหัสผ่านใหม่:", QLineEdit.EchoMode.Password)
        if ok and new_pw:
            try:
                self.service.reset_password(user_id, new_pw)
                QMessageBox.information(self, "สำเร็จ", "รีเซ็ตรหัสผ่านเรียบร้อย")
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def on_toggle_active(self, user_id, new_state):
        try:
            self.service.update_user(user_id, is_active=new_state)
            self.load_users()
        except Exception as e:
            QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))

    def on_delete_user(self, user_id, username):
        reply = QMessageBox.question(
            self, "ยืนยันการลบ",
            f"ต้องการลบผู้ใช้ '{username}' หรือไม่?\nการดำเนินการนี้ไม่สามารถย้อนกลับได้!",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            try:
                self.service.delete_user(user_id)
                self.load_users()
            except Exception as e:
                QMessageBox.critical(self, "เกิดข้อผิดพลาด", str(e))


# ─── About Page ───────────────────────────────────────────────
class AboutPage(QWidget):
    def __init__(self):

        super().__init__()
        root = QVBoxLayout(self)
        root.setContentsMargins(32, 24, 32, 32)
        root.setSpacing(0)

        root.addWidget(make_label("เกี่ยวกับโปรแกรม", 20, bold=True))
        root.addSpacing(4)
        root.addWidget(make_label("About Maintenance Super App", 12, color=TEXT_MUTED))
        root.addSpacing(16)
        root.addWidget(make_separator())
        root.addSpacing(20)

        # ── App hero card ─────────────────────────────────────
        hero = QFrame()
        hero.setObjectName("card")
        hl = QVBoxLayout(hero)
        hl.setContentsMargins(28, 24, 28, 24)
        hl.setSpacing(6)

        logo = make_label("⚙️", 40)
        logo.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hl.addWidget(logo)

        app_name = make_label("Maintenance Super App", 22, bold=True)
        app_name.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hl.addWidget(app_name)

        ver_lbl = make_label("Version 3.3  •  2026", 12, color=TEXT_MUTED)
        ver_lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hl.addWidget(ver_lbl)

        slogan = make_label(
            "ระบบจัดการงานซ่อมบำรุงเครื่องจักรครบวงจร สำหรับอุตสาหกรรมการผลิต",
            11, color=TEXT_MUTED
        )
        slogan.setAlignment(Qt.AlignmentFlag.AlignCenter)
        slogan.setWordWrap(True)
        hl.addWidget(slogan)

        root.addWidget(hero)
        root.addSpacing(20)

        # ── Two-column info ────────────────────────────────────
        cols = QHBoxLayout()
        cols.setSpacing(16)

        # Left: Tech stack
        left = QFrame()
        left.setObjectName("card")
        ll = QVBoxLayout(left)
        ll.setContentsMargins(20, 16, 20, 16)
        ll.setSpacing(10)
        ll.addWidget(make_label("🛠  เทคโนโลยีที่ใช้", 13, bold=True))
        ll.addWidget(make_separator())

        techs = [
            ("Language",   "Python 3.10+"),
            ("GUI",         "PyQt6"),
            ("Database",   "SQLite / PostgreSQL"),
            ("ORM",        "SQLAlchemy 2.0"),
            ("QR Code",    "qrcode + Pillow"),
            ("PDF",        "ReportLab"),
            ("Charts",     "Matplotlib"),
        ]
        for k, v in techs:
            row_w = QHBoxLayout()
            row_w.setSpacing(0)
            k_lbl = make_label(k, 12, color=TEXT_MUTED)
            k_lbl.setFixedWidth(100)
            v_lbl = make_label(v, 12, color=TEXT_PRIMARY)
            row_w.addWidget(k_lbl)
            row_w.addWidget(v_lbl)
            row_w.addStretch()
            ll.addLayout(row_w)

        ll.addStretch()
        cols.addWidget(left)

        # Right: Screen support + modules
        right = QFrame()
        right.setObjectName("card")
        rl = QVBoxLayout(right)
        rl.setContentsMargins(20, 16, 20, 16)
        rl.setSpacing(10)
        rl.addWidget(make_label("🖥  ความต้องการระบบ", 13, bold=True))
        rl.addWidget(make_separator())

        specs = [
            ("ความละเอียดขั้นต่ำ",  "1280 × 720  (HD)"),
            ("แนะนำ",              "1920 × 1080  (Full HD)"),
            ("รองรับสูงสุด",        "4K / UHD (Scale-aware)"),
            ("OS",                  "Windows 10 / 11"),
            ("RAM ขั้นต่ำ",         "4 GB"),
            ("Network",             "LAN / Shared Drive"),
            ("Python",              "3.10 ขึ้นไป"),
        ]
        for k, v in specs:
            row_w = QHBoxLayout()
            row_w.setSpacing(0)
            k_lbl = make_label(k, 12, color=TEXT_MUTED)
            k_lbl.setFixedWidth(150)
            v_lbl = make_label(v, 12, color=TEXT_PRIMARY)
            row_w.addWidget(k_lbl)
            row_w.addWidget(v_lbl)
            row_w.addStretch()
            rl.addLayout(row_w)

        rl.addSpacing(12)
        rl.addWidget(make_label("📦  8 โมดูลหลัก", 13, bold=True))
        rl.addWidget(make_separator())

        modules = [
            "1. ทะเบียนเครื่องจักร & Digital Handover",
            "2. Factory Layout Visualization",
            "3. Knowledge Base (MTBF / MTTR / OEE)",
            "4. Preventive Maintenance (PM)",
            "5. Repair & Root Cause (5 Whys)",
            "6. Spare Parts & Procurement",
            "7. Analytics Dashboard",
            "8. Admin, RBAC & Audit Logs",
        ]
        for m in modules:
            ml = make_label(f"  {m}", 11, color=TEXT_MUTED)
            rl.addWidget(ml)

        rl.addStretch()
        cols.addWidget(right)

        root.addLayout(cols)
        root.addSpacing(16)

        # ── Footer ─────────────────────────────────────────────
        footer = make_label(
            "© 2026  Maintenance Super App v3.3  •  Developed for Factory Maintenance Departments",
            10, color=TEXT_MUTED
        )
        footer.setAlignment(Qt.AlignmentFlag.AlignCenter)
        root.addWidget(footer)


# ─── Placeholder pages ─────────────────────────────────────────
def placeholder_page(icon, title, subtitle):
    w = QWidget()
    l = QVBoxLayout(w)
    l.setAlignment(Qt.AlignmentFlag.AlignCenter)
    l.setSpacing(8)
    ico = make_label(icon, 48, color=TEXT_MUTED)
    ico.setAlignment(Qt.AlignmentFlag.AlignCenter)
    ttl = make_label(title, 18, bold=True, color=TEXT_MUTED)
    ttl.setAlignment(Qt.AlignmentFlag.AlignCenter)
    sub = make_label(subtitle, 12, color=TEXT_MUTED)
    sub.setAlignment(Qt.AlignmentFlag.AlignCenter)
    l.addWidget(ico)
    l.addWidget(ttl)
    l.addWidget(sub)
    return w


# =====================================================================
# Settings Page
# =====================================================================
class SettingsPage(QWidget):
    def __init__(self, current_user=None, parent=None):
        super().__init__(parent)
        self.current_user = current_user
        self.setObjectName("page_bg")
        self._build_ui()
        self._load_data()

    def _build_ui(self):
        from views import ThemeManager
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(40, 40, 40, 40)
        main_layout.setSpacing(20)

        # Header
        header = QLabel("⚙  ตั้งค่าระบบ (System Settings)")
        header.setStyleSheet(f"font-size: 24px; font-weight: bold; color: {ThemeManager.c('TEXT_PRIMARY')}; background: transparent;")
        main_layout.addWidget(header)

        # Card container
        card = QFrame()
        card.setObjectName("card")
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(30, 30, 30, 30)
        card_layout.setSpacing(20)

        title = QLabel("📝 Logo เอกสารสำหรับพิมพ์")
        title.setStyleSheet(f"font-size: 16px; font-weight: bold; color: {ThemeManager.c('TEXT_PRIMARY')}; background: transparent;")
        card_layout.addWidget(title)

        desc = QLabel("ระบุรูปภาพโลโก้บริษัทที่จะนำไปแสดงอัตโนมัติที่มุมบนซ้ายของเอกสารสั่งพิมพ์ทั้งหมด (เช่น ใบรับเครื่องจักร)")
        desc.setStyleSheet(f"font-size: 13px; color: {ThemeManager.c('TEXT_MUTED')}; background: transparent;")
        desc.setWordWrap(True)
        card_layout.addWidget(desc)

        # Logo display area
        self.logo_display = QLabel("ยังไม่ได้ตั้งค่า Logo")
        self.logo_display.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.logo_display.setFixedSize(300, 100)
        self.logo_display.setStyleSheet(f"border: 2px dashed {ThemeManager.c('BORDER')}; background: {ThemeManager.c('BG_CARD')}; color: {ThemeManager.c('TEXT_MUTED')};")
        card_layout.addWidget(self.logo_display, alignment=Qt.AlignmentFlag.AlignLeft)

        # Upload button
        upload_btn = QPushButton("📎 เลือกไฟล์ภาพ Logo")
        upload_btn.setObjectName("btn_secondary")
        upload_btn.setFixedWidth(200)
        upload_btn.clicked.connect(self._pick_logo)
        card_layout.addWidget(upload_btn, alignment=Qt.AlignmentFlag.AlignLeft)

        main_layout.addWidget(card)
        main_layout.addStretch()

    def _load_data(self):
        from services import SettingsService
        from PyQt6.QtGui import QPixmap
        from views import ThemeManager
        logo_path = SettingsService.get_setting("company_logo_path")
        if logo_path:
            pixmap = QPixmap(logo_path)
            if not pixmap.isNull():
                self.logo_display.setPixmap(pixmap.scaled(self.logo_display.size(), Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
                self.logo_display.setStyleSheet(f"border: 1px solid {ThemeManager.c('BORDER')}; background: transparent;")
            else:
                self.logo_display.setText("⚠️ ไฟล์ Logo ไม่ถูกต้องหรือสูญหาย")

    def _pick_logo(self):
        from PyQt6.QtWidgets import QFileDialog, QMessageBox
        from services import SettingsService
        p, _ = QFileDialog.getOpenFileName(self, "เลือกภาพ Logo", "", "Images (*.png *.jpg *.jpeg)")
        if p:
            try:
                SettingsService.set_setting("company_logo_path", p)
                self._load_data()
                QMessageBox.information(self, "สำเร็จ", "บันทึก Logo เข้าระบบเรียบร้อยแล้ว")
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", f"ไม่สามารถบันทึกข้อมุลได้:\n{str(e)}")


# ─── AM DASHBOARD PAGE (Operator View) ────────────────────────
class AMDashboardPage(QWidget):
    def __init__(self, current_user=None):
        super().__init__()
        self.current_user = current_user
        from services import MachineService, PMService, WorkOrderService
        self.machine_svc = MachineService()
        self.pm_svc      = PMService()
        self.wo_svc      = WorkOrderService()
        if self.current_user:
            self.machine_svc.set_current_user(self.current_user)
            self.pm_svc.set_current_user(self.current_user)
            self.wo_svc.set_current_user(self.current_user)
        self._build_ui()
        self.refresh()

    def refresh(self):
        # Load machines that have active AM plans or tasks
        machines = self.machine_svc.get_all_machines()
        self._render_machine_list(machines)

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 24, 24, 24)
        root.setSpacing(20)

        # Header
        header = QHBoxLayout()
        header.addWidget(make_label("⚡ AM DASHBOARD (Autonomous Maintenance)", 20, bold=True))
        header.addStretch()
        refresh_btn = QPushButton("🔄  รีเฟรช")
        refresh_btn.clicked.connect(self.refresh)
        header.addWidget(refresh_btn)
        root.addLayout(header)

        # Main Layout: Machine List (Left) | Task Detail (Right)
        main_h = QHBoxLayout()
        root.addLayout(main_h)

        # Machine List (Cards)
        self.list_scroll = QScrollArea()
        self.list_scroll.setWidgetResizable(True)
        self.list_scroll.setFixedWidth(350)
        self.list_scroll.setStyleSheet(f"background: transparent; border: none;")
        self.list_container = QWidget()
        self.list_layout = QVBoxLayout(self.list_container)
        self.list_layout.setAlignment(Qt.AlignmentFlag.AlignTop)
        self.list_scroll.setWidget(self.list_container)
        main_h.addWidget(self.list_scroll)

        # Task Detail Area
        self.detail_area = QFrame()
        self.detail_area.setStyleSheet(f"background: {ThemeManager.c('BG_PANEL')}; border-radius: 12px; border: 1px solid {ThemeManager.c('BORDER')};")
        self.detail_lay = QVBoxLayout(self.detail_area)
        self.detail_lay.setContentsMargins(30, 30, 30, 30)
        self.detail_lay.setAlignment(Qt.AlignmentFlag.AlignCenter)
        
        self.no_selection_lbl = QLabel("🔔 กรุณาเลือกเครื่องจักรเพื่อเริ่มทำ AM")
        self.no_selection_lbl.setStyleSheet(f"color: {ThemeManager.c('TEXT_MUTED')}; font-size: 14px;")
        self.detail_lay.addWidget(self.no_selection_lbl)
        
        main_h.addWidget(self.detail_area, 1)

    def _render_machine_list(self, machines):
        # Clear existing
        while self.list_layout.count():
            it = self.list_layout.takeAt(0)
            if it.widget(): it.widget().deleteLater()

        for m in machines:
            card = QFrame()
            card.setObjectName("am_machine_card")
            card.setStyleSheet(f"""
                #am_machine_card {{ 
                    background: {ThemeManager.c('BG_CARD')}; border-radius: 8px; border: 1px solid {ThemeManager.c('BORDER')}; 
                    padding: 12px; 
                }}
                #am_machine_card:hover {{ border: 1.5px solid {ThemeManager.c('ACCENT')}; }}
            """)
            cl = QVBoxLayout(card)
            cl.addWidget(make_label(m.code, 12, bold=True, color=ThemeManager.c('ACCENT_LIGHT')))
            cl.addWidget(make_label(m.name, 14, bold=True))
            
            # Show if there is a pending AM Work Order
            pending_am = self.wo_svc.db.query(models.WorkOrder).filter(
                models.WorkOrder.machine_id == m.id,
                models.WorkOrder.wo_type == "AM",
                models.WorkOrder.status.in_(["Open", "Progress"])
            ).first()

            status_lay = QHBoxLayout()
            if pending_am:
                badge = QLabel("  มีงานค้าง  ")
                badge.setStyleSheet(f"background: {ThemeManager.c('YELLOW')}; color: white; border-radius: 4px; font-size: 10px; font-weight: bold;")
            else:
                badge = QLabel("  ปกติ  ")
                badge.setStyleSheet(f"background: {ThemeManager.c('ACCENT')}; color: white; border-radius: 4px; font-size: 10px;")
            
            status_lay.addWidget(badge)
            status_lay.addStretch()
            cl.addLayout(status_lay)

            card.mousePressEvent = lambda e, mac=m: self._select_machine(mac)
            card.setCursor(Qt.CursorShape.PointingHandCursor)
            self.list_layout.addWidget(card)
        
        self.list_layout.addStretch()

    def _select_machine(self, machine):
        # Clear detail area
        while self.detail_lay.count():
            it = self.detail_lay.takeAt(0)
            if it.widget(): it.widget().deleteLater()
        
        self.detail_lay.setAlignment(Qt.AlignmentFlag.AlignTop)
        
        # Header Info
        header_lay = QHBoxLayout()
        header_lay.addWidget(make_label(f"🛠️ {machine.name} ({machine.code})", 18, bold=True))
        header_lay.addStretch()
        self.detail_lay.addLayout(header_lay)
        
        self.detail_lay.addWidget(make_separator())
        
        # Check for open AM Work Order
        wo = self.wo_svc.db.query(models.WorkOrder).filter(
            models.WorkOrder.machine_id == machine.id,
            models.WorkOrder.wo_type == "AM",
            models.WorkOrder.status.in_(["Open", "Progress"])
        ).first()

        if not wo:
            # Check if we should generate tasks first
            self.pm_svc.generate_tasks_for_due_plans()
            wo = self.wo_svc.db.query(models.WorkOrder).filter(
                models.WorkOrder.machine_id == machine.id,
                models.WorkOrder.wo_type == "AM",
                models.WorkOrder.status.in_(["Open", "Progress"])
            ).first()

        if not wo:
            msg = QLabel("🌴 ไม่มีรายการบำรุงรักษา (AM) ที่ต้องทำในตอนนี้")
            msg.setStyleSheet(f"color: {ThemeManager.c('TEXT_MUTED')}; font-size: 15px; margin-top: 40px;")
            self.detail_lay.addWidget(msg, 0, Qt.AlignmentFlag.AlignCenter)
            
            # Option to manually start an AM if needed? For now just show "Create Defect"
            btn_defect = QPushButton("🚩 แจ้งพบความผิดปกติ (Defect Card)")
            btn_defect.setObjectName("btn_secondary")
            btn_defect.setFixedWidth(250)
            self.detail_lay.addSpacing(20)
            self.detail_lay.addWidget(btn_defect, 0, Qt.AlignmentFlag.AlignCenter)
            return

        # Render the checklist from the Work Order
        self.detail_lay.addWidget(make_label(f"📋 รายการตรวจสอบ AM - เลขที่งาน: #{wo.id}", 14, bold=True))
        
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet("background: transparent; border: none;")
        scroll_content = QWidget()
        scroll_lay = QVBoxLayout(scroll_content)
        scroll_lay.setSpacing(10)
        
        results = wo.checklist_results
        self._check_boxes = {} # Store for submission

        for r in results:
            row = QFrame()
            row.setStyleSheet(f"background: {ThemeManager.c('BG_DARK')}; border-radius: 8px; padding: 12px;")
            rl = QHBoxLayout(row)
            
            cb = QCheckBox()
            cb.setChecked(r.is_checked)
            rl.addWidget(cb)
            
            lbl = QLabel(r.task_name)
            lbl.setWordWrap(True)
            rl.addWidget(lbl, 1)
            
            # If it's a parameter reading
            if r.checklist_item and r.checklist_item.is_parameter:
                unit = r.checklist_item.parameter_unit or ""
                val_input = QLineEdit()
                val_input.setPlaceholderText(f"ระบุค่า ({unit})")
                val_input.setFixedWidth(120)
                val_input.setText(r.parameter_value or "")
                rl.addWidget(val_input)
                self._check_boxes[r.id] = (cb, val_input)
            else:
                self._check_boxes[r.id] = (cb, None)
                
            scroll_lay.addWidget(row)
        
        scroll_lay.addStretch()
        scroll.setWidget(scroll_content)
        self.detail_lay.addWidget(scroll)
        
        # Photo Evidence Area
        self.detail_lay.addSpacing(10)
        self.detail_lay.addWidget(make_label("📸 รูปถ่ายหลักฐาน (Photo Evidence)", 13, bold=True))
        
        self.photo_scroll = QScrollArea()
        self.photo_scroll.setWidgetResizable(True)
        self.photo_scroll.setFixedHeight(110)
        self.photo_scroll.setStyleSheet("background: transparent; border: 1px dashed #30363D; border-radius: 8px;")
        
        self.photo_container = QWidget()
        self.photo_lay = QHBoxLayout(self.photo_container)
        self.photo_lay.setAlignment(Qt.AlignmentFlag.AlignLeft)
        self.photo_scroll.setWidget(self.photo_container)
        self.detail_lay.addWidget(self.photo_scroll)
        
        self._refresh_photos(wo.id)
        
        # Footer Actions
        self.detail_lay.addSpacing(10)
        footer = QHBoxLayout()
        
        defect_btn = QPushButton("🚩 แจ้งพบความผิดปกติ")
        defect_btn.setStyleSheet(f"background: {ThemeManager.c('RED')}; color: white; padding: 10px 20px; font-weight: bold;")
        defect_btn.clicked.connect(lambda: self._report_defect(machine, wo))
        footer.addWidget(defect_btn)

        upload_btn = QPushButton("📷 แนบรูปภาพ")
        upload_btn.setObjectName("btn_secondary")
        upload_btn.setFixedHeight(40)
        upload_btn.clicked.connect(lambda: self._upload_photo(wo.id))
        footer.addWidget(upload_btn)
        
        footer.addStretch()
        
        save_btn = QPushButton("✅ บันทึกและปิดงาน")
        save_btn.setStyleSheet(f"background: {ThemeManager.c('ACCENT')}; color: white; font-weight: bold; padding: 10px 25px; font-size: 14px;")
        save_btn.clicked.connect(lambda: self._submit_am(wo))
        footer.addWidget(save_btn)
        
        self.detail_lay.addLayout(footer)

    def _submit_am(self, wo):
        data_results = {}
        for res_id, (cb, val_in) in self._check_boxes.items():
            data_results[res_id] = {
                "is_checked": cb.isChecked(),
                "parameter_value": val_in.text() if val_in else None
            }
        
        try:
            # Mark WO as Closed
            self.wo_svc.update_work_order(wo.id, {"status": "Closed"}, checklist_results=data_results)
            QMessageBox.information(self, "แจ้งเตือน", "บันทึกผลการทำ AM เรียบร้อยแล้ว")
            self.refresh()
            # Clear details
            self._select_machine(self.wo_svc.db.query(models.Machine).get(wo.machine_id))
        except Exception as e:
            QMessageBox.critical(self, "ข้อผิดพลาด", f"ไม่สามารถบันทึกข้อมูลได้: {e}")

    def _refresh_photos(self, wo_id):
        while self.photo_lay.count():
            it = self.photo_lay.takeAt(0)
            if it.widget(): it.widget().deleteLater()
        
        atts = self.wo_svc.get_attachments(wo_id)
        if not atts:
            lbl = QLabel("ยังไม่มีรูปถ่าย")
            lbl.setStyleSheet(f"color: {ThemeManager.c('TEXT_MUTED')}; font-size: 11px;")
            self.photo_lay.addWidget(lbl)
            return

        for att in atts:
            if os.path.exists(att.file_path):
                img = QLabel()
                pix = QPixmap(att.file_path).scaled(80, 80, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
                img.setPixmap(pix)
                img.setToolTip("คลิกเพื่อดูรูปใหญ่")
                img.setCursor(Qt.CursorShape.PointingHandCursor)
                img.mousePressEvent = lambda e, p=att.file_path: self._view_large_photo(p)
                self.photo_lay.addWidget(img)
        self.photo_lay.addStretch()

    def _upload_photo(self, wo_id):
        path, _ = QFileDialog.getOpenFileName(self, "เลือกรูปถ่าย", "", "Images (*.png *.jpg *.jpeg *.bmp)")
        if path:
            try:
                self.wo_svc.add_attachment(wo_id, path)
                self._refresh_photos(wo_id)
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", f"ไม่สามารถแนบรูปได้: {e}")

    def _view_large_photo(self, path):
        dlg = QDialog(self)
        dlg.setWindowTitle("ดูรูปภาพหลักฐาน")
        l = QVBoxLayout(dlg)
        img = QLabel()
        pix = QPixmap(path)
        # Scale to fit screen but keep aspect ratio
        screen_size = self.screen().size()
        pix = pix.scaled(int(screen_size.width()*0.6), int(screen_size.height()*0.6), Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation)
        img.setPixmap(pix)
        l.addWidget(img)
        dlg.exec()

    def _report_defect(self, machine, wo=None):
        dlg = DefectCardDialog(machine, self)
        if dlg.exec():
            try:
                data = dlg.get_data()
                if wo:
                    data["description"] = f"[จากใบสั่งงาน AM #{wo.id}] " + data["description"]
                self.wo_svc.create_work_order(data)
                QMessageBox.information(self, "สำเร็จ", "สร้างใบแจ้งซ่อม (Defect Card) เรียบร้อยแล้ว")
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", str(e))

class DefectCardDialog(QDialog):
    def __init__(self, machine, parent=None):
        super().__init__(parent)
        self.setWindowTitle("แจ้งพบความผิดปกติ (Defect Card)")
        self.setFixedWidth(450)
        self.machine = machine
        self._build_ui()

    def _build_ui(self):
        lay = QFormLayout(self)
        lay.addRow(make_label(f"🚨 แจ้งซ่อมเครื่องจักร: {self.machine.name}", 14, bold=True))
        
        self.desc_in = QLineEdit()
        self.desc_in.setPlaceholderText("ระบุอาการเสีย / ความผิดปกติที่พบ...")
        lay.addRow("รายละเอียด:", self.desc_in)
        
        self.priority_cb = QComboBox()
        self.priority_cb.addItems(["Normal", "High", "Critical"])
        lay.addRow("ความเร่งด่วน:", self.priority_cb)
        
        btns = QHBoxLayout()
        save = QPushButton("ส่งแจ้งซ่อม")
        save.setStyleSheet(f"background: {ThemeManager.c('RED')}; color: white; font-weight: bold;")
        save.clicked.connect(self.accept)
        
        cancel = QPushButton("ยกเลิก")
        cancel.clicked.connect(self.reject)
        
        btns.addWidget(save)
        btns.addWidget(cancel)
        lay.addRow(btns)

    def get_data(self):
        return {
            "machine_id": self.machine.id,
            "wo_type": "Repair",
            "description": self.desc_in.text(),
            "priority": self.priority_cb.currentText(),
            "status": "Open"
        }

# ─── PM PLANS MANAGEMENT PAGE ──────────────────────────────────
class PMPlansPage(QWidget):
    def __init__(self, current_user=None):
        super().__init__()
        self.current_user = current_user
        from services import PMService, MachineService, WorkOrderService
        self.svc = PMService()
        self.machine_svc = MachineService()
        self.wo_svc = WorkOrderService()
        self.report_svc = ReportingService()
        if self.current_user:
            self.svc.set_current_user(self.current_user)
            self.machine_svc.set_current_user(self.current_user)
            self.wo_svc.set_current_user(self.current_user)
            self.report_svc.set_current_user(self.current_user)
        self._build_ui()
        self.refresh()

    def refresh(self):
        self._refresh_plans()
        self._refresh_tasks()

    def _refresh_plans(self):
        plans = self.svc.get_all_plans()
        
        # Filter by Type
        type_idx = self.type_filter.currentIndex()
        if type_idx == 1: # AM
            plans = [p for p in plans if p.plan_type == "AM"]
        elif type_idx == 2: # PM
            plans = [p for p in plans if p.plan_type == "PM"]
            
        # Filter by Search Text
        search = self.search_in.text().lower().strip()
        if search:
            plans = [p for p in plans if (
                search in (p.machine.name or "").lower() or 
                search in (p.machine.code or "").lower() or
                search in (p.title or "").lower()
            )]
            
        self.table.setRowCount(len(plans))
        
        for i, p in enumerate(plans):
            self.table.setItem(i, 0, QTableWidgetItem(p.plan_type))
            self.table.setItem(i, 1, QTableWidgetItem(f"{p.machine.code} - {p.machine.name}" if p.machine else "-"))
            
            sched_th = "รอบปฏิทิน" if p.schedule_type == "Calendar" else "ตามเงื่อนไข"
            self.table.setItem(i, 2, QTableWidgetItem(sched_th if p.plan_type == "PM" else "-"))
            
            due_str = p.next_due_date.strftime("%d/%m/%Y") if p.next_due_date and p.plan_type == "PM" else "-"
            self.table.setItem(i, 3, QTableWidgetItem(due_str))
            
            btn_box = self._make_plan_actions(p)
            self.table.setCellWidget(i, 4, btn_box)

    def _make_plan_actions(self, p):
        btn_box = QWidget()
        bl = QHBoxLayout(btn_box)
        bl.setContentsMargins(4, 2, 4, 2)
        
        edit_btn = QPushButton("✏️")
        edit_btn.setToolTip("แก้ไขแผน")
        edit_btn.setFixedSize(30, 30)
        edit_btn.clicked.connect(lambda _, plan=p: self._edit_plan(plan))
        
        list_btn = QPushButton("📋")
        list_btn.setToolTip("จัดการรายละเอียดการตรวจสอบและมาตรฐาน")
        list_btn.setFixedSize(30, 30)
        list_btn.clicked.connect(lambda _, plan=p: self._manage_checklist(plan))
        
        print_btn = QPushButton("🖨️")
        print_btn.setToolTip("พิมพ์ใบเช็คสลิสต์ (PDF)")
        print_btn.setFixedSize(30, 30)
        print_btn.clicked.connect(lambda _, plan_id=p.id: self._print_checksheet(plan_id))

        del_btn = QPushButton("🗑️")
        del_btn.setToolTip("ลบแผน")
        del_btn.setFixedSize(30, 30)
        del_btn.clicked.connect(lambda _, pid=p.id: self._delete_plan(pid))
        
        bl.addWidget(edit_btn)
        bl.addWidget(list_btn)
        bl.addWidget(print_btn)
        bl.addWidget(del_btn)
        return btn_box

    def _edit_plan(self, plan):
        from services import MachineService
        machines = MachineService().get_all_machines()
        dlg = AddPMPlanDialog(machines, self, plan=plan)
        if dlg.exec():
            try:
                self.svc.update_plan(plan.id, dlg.get_data())
                QMessageBox.information(self, "สำเร็จ", "อัปเดตแผนการบำรุงรักษาเรียบร้อยแล้ว")
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", str(e))

    def _refresh_tasks(self):
        # Fetch PM work orders (AM is skipped per user request as operators have no computers)
        pm_wos = [wo for wo in self.wo_svc.get_all_work_orders() if wo.wo_type == "PM" and wo.status != "Closed"]
        self.task_table.setRowCount(len(pm_wos))
        for i, wo in enumerate(pm_wos):
            self.task_table.setItem(i, 0, QTableWidgetItem(wo.wo_type))
            self.task_table.setItem(i, 1, QTableWidgetItem(wo.machine.name if wo.machine else "-"))
            self.task_table.setItem(i, 2, QTableWidgetItem(wo.description))
            self.task_table.setItem(i, 3, QTableWidgetItem(wo.status))
            
            created_str = wo.created_at.strftime("%d/%m/%Y %H:%M") if wo.created_at else "-"
            self.task_table.setItem(i, 4, QTableWidgetItem(created_str))

            # Actions
            btn = QPushButton("✅ ปิดงาน (Close)")
            btn.setObjectName("btn_accent")
            btn.setFixedHeight(28)
            btn.clicked.connect(lambda _, w=wo: self._close_task(w))
            self.task_table.setCellWidget(i, 5, btn)

    def _build_ui(self):
        root = QVBoxLayout(self)
        root.setContentsMargins(12, 12, 12, 12)
        
        self.tabs = QTabWidget()
        self.tabs.addTab(self._tab_plans(), "📅 แผนการบำรุงรักษา (Plans)")
        self.tabs.addTab(self._tab_tasks(), "🛠️ รายการงานที่ต้องทำ (Work Orders)")
        root.addWidget(self.tabs)

    def _tab_plans(self):
        page = QWidget()
        lay = QVBoxLayout(page)
        lay.setContentsMargins(12, 12, 12, 12)

        header = QHBoxLayout()
        header.addWidget(make_label("📅 รายการแผนการบำรุงรักษา (AM/PM Plans)", 18, bold=True))
        header.addStretch()
        
        add_btn = QPushButton("➕ สร้างแผนใหม่")
        add_btn.setObjectName("btn_primary")
        add_btn.clicked.connect(self._add_plan)
        header.addWidget(add_btn)
        lay.addLayout(header)

        # Filter Bar
        filter_layout = QHBoxLayout()
        filter_layout.addWidget(make_label("🔍 ตัวกรอง:", 14))
        
        self.type_filter = QComboBox()
        self.type_filter.addItems(["ทั้งหมด (All)", "AM (พนักงาน)", "PM (ช่าง)"])
        self.type_filter.currentIndexChanged.connect(self._refresh_plans)
        filter_layout.addWidget(self.type_filter)
        
        self.search_in = QLineEdit()
        self.search_in.setPlaceholderText("ระบุ ชื่อเครื่อง, รหัสเครื่อง หรือรายละเอียด...")
        self.search_in.textChanged.connect(self._refresh_plans)
        filter_layout.addWidget(self.search_in)
        
        lay.addLayout(filter_layout)

        self.table = QTableWidget()
        self.table.verticalHeader().setDefaultSectionSize(40)
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels(["ประเภท", "เครื่องจักร", "รูปแบบ", "กำหนดการถัดไป", "จัดการ"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        self.table.setColumnWidth(4, 160)
        lay.addWidget(self.table)
        return page

    def _tab_tasks(self):
        page = QWidget()
        lay = QVBoxLayout(page)
        lay.setContentsMargins(12, 12, 12, 12)
        
        lay.addWidget(make_label("🛠️ รายการงานบำรุงรักษาที่ค้างอยู่ (Active PM/AM)", 18, bold=True))

        self.task_table = QTableWidget()
        self.task_table.verticalHeader().setDefaultSectionSize(40)
        self.task_table.setColumnCount(6)
        self.task_table.setHorizontalHeaderLabels(["ประเภท", "เครื่องจักร", "รายละเอียด", "สถานะ", "วันที่สั่งงาน", "จัดการ"])
        self.task_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        lay.addWidget(self.task_table)
        return page

    def _add_plan(self):
        from services import MachineService
        machines = MachineService().get_all_machines()
        dlg = AddPMPlanDialog(machines, self)
        if dlg.exec():
            try:
                self.svc.create_plan(dlg.get_data())
                QMessageBox.information(self, "สำเร็จ", "สร้างแผนการบำรุงรักษาเรียบร้อยแล้ว")
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", str(e))

    def _manage_checklist(self, plan):
        dlg = ChecklistEditorDialog(plan, self)
        dlg.exec()
        self.refresh()

    def _delete_plan(self, pid):
        if QMessageBox.question(self, "ยืนยัน", "ต้องการลบแผนนี้ใช่หรือไม่?") == QMessageBox.StandardButton.Yes:
            self.svc.delete_plan(pid)
            self.refresh()

    def _print_checksheet(self, plan_id):
        try:
            pdf_path = self.report_svc.generate_am_checksheet(plan_id)
            if os.path.exists(pdf_path):
                os.startfile(pdf_path) # Works on Windows
                # QMessageBox.information(self, "สำเร็จ", f"สร้างไฟล์ PDF เรียบร้อยแล้ว:\n{pdf_path}")
        except Exception as e:
            QMessageBox.critical(self, "ข้อผิดพลาด", f"ไม่สามารถสร้าง PDF ได้: {e}")

    def _close_task(self, wo):
        dlg = CloseWorkOrderDialog(wo, self)
        if dlg.exec():
            try:
                self.wo_svc.update_work_order(wo.id, dlg.get_data())
                # Update Plan next due date if it was a PM/AM from plan
                if wo.pm_plan_id:
                    self.svc.update_plan_after_task(wo.pm_plan_id)
                
                QMessageBox.information(self, "สำเร็จ", "ปิดงานเรียบร้อยแล้ว")
                self.refresh()
            except Exception as e:
                QMessageBox.critical(self, "ข้อผิดพลาด", str(e))

class CloseWorkOrderDialog(QDialog):
    def __init__(self, wo, parent=None):
        super().__init__(parent)
        self.setWindowTitle(f"ปิดงาน: #{wo.id}")
        self.setFixedWidth(400)
        self._build_ui()

    def _build_ui(self):
        lay = QFormLayout(self)
        self.minutes_in = QLineEdit()
        self.minutes_in.setPlaceholderText("ระบุเวลาที่ใช้ (นาที)")
        lay.addRow("เวลาที่ใช้ (นาที):", self.minutes_in)
        
        self.action_in = QLineEdit()
        self.action_in.setPlaceholderText("สรุปการดำเนินการ...")
        lay.addRow("สรุปงาน:", self.action_in)
        
        btns = QHBoxLayout()
        save = QPushButton("บันทึกปิดงาน")
        save.setObjectName("btn_accent")
        save.clicked.connect(self.accept)
        cancel = QPushButton("ยกเลิก")
        cancel.clicked.connect(self.reject)
        btns.addWidget(save)
        btns.addWidget(cancel)
        lay.addRow(btns)

    def get_data(self):
        return {
            "status": "Closed",
            "actual_minutes": int(self.minutes_in.text()) if self.minutes_in.text().isdigit() else 0,
            "action_taken": self.action_in.text(),
            "closed_at": datetime.now()
        }

class AddPMPlanDialog(QDialog):
    def __init__(self, machines, parent=None, plan=None):
        super().__init__(parent)
        self.plan = plan
        self.setWindowTitle("แก้ไขแผนการบำรุงรักษา" if plan else "สร้างแผนการบำรุงรักษา")
        self.setFixedWidth(500)
        self.machines = machines
        self._build_ui()
        if plan:
            self._fill_data()

    def _fill_data(self):
        # Set Type
        idx = 0 if self.plan.plan_type == "PM" else 1
        self.type_cb.setCurrentIndex(idx)
        
        # Set Machine
        for i in range(self.machine_cb.count()):
            if self.machine_cb.itemData(i) == self.plan.machine_id:
                self.machine_cb.setCurrentIndex(i)
                break
        
        self.detail_in.setText(self.plan.title)
        self.standard_in.setText(self.plan.standard or "")
        self.note_in.setText(self.plan.description or "")
        
        # Frequency
        for i in range(self.freq_cb.count()):
            if self.freq_cb.itemData(i) == self.plan.frequency_days:
                self.freq_cb.setCurrentIndex(i)
                break

    def _build_ui(self):
        lay = QFormLayout(self)
        
        self.type_cb = QComboBox()
        self.type_cb.addItems(["PM (ช่างบำรุงรักษา)", "AM (พนักงานฝ่ายผลิต)"])
        lay.addRow("ประเภทงาน:", self.type_cb)
        
        self.machine_cb = QComboBox()
        for m in self.machines:
            self.machine_cb.addItem(f"{m.code} - {m.name}", m.id)
        lay.addRow("เครื่องจักร:", self.machine_cb)

        self.detail_in = QLineEdit()
        self.detail_in.setPlaceholderText("เช่น ตรวจเช็คสายพาน, ทาจาระบี")
        lay.addRow("รายละเอียดการตรวจสอบ:", self.detail_in)

        self.standard_in = QLineEdit()
        self.standard_in.setPlaceholderText("เช่น ไม่หย่อน, มีจาระบีหล่อลื่น")
        lay.addRow("มาตรฐานการตรวจ:", self.standard_in)

        self.freq_cb = QComboBox()
        # Add labels with day values as data
        self.freq_cb.addItem("รายวัน (Daily)", 1)
        self.freq_cb.addItem("รายสัปดาห์ (Weekly)", 7)
        self.freq_cb.addItem("รายปักษ์ (15 วัน)", 15)
        self.freq_cb.addItem("รายเดือน (Monthly)", 30)
        self.freq_cb.addItem("ทุก 3 เดือน", 90)
        self.freq_cb.addItem("ทุก 6 เดือน (1/2 Year)", 180)
        self.freq_cb.addItem("รายปี (Yearly)", 365)
        lay.addRow("ความถี่:", self.freq_cb)

        self.note_in = QLineEdit()
        self.note_in.setPlaceholderText("ระบุหมายเหตุเพิ่มเติม (ถ้ามี)...")
        lay.addRow("หมายเหตุ:", self.note_in)
        
        btns = QHBoxLayout()
        save = QPushButton("บันทึก")
        save.setObjectName("btn_primary")
        save.clicked.connect(self.accept)
        cancel = QPushButton("ยกเลิก")
        cancel.clicked.connect(self.reject)
        btns.addWidget(save)
        btns.addWidget(cancel)
        lay.addRow(btns)

    def get_data(self):
        return {
            "plan_type": "PM" if "PM" in self.type_cb.currentText() else "AM",
            "machine_id": self.machine_cb.currentData(),
            "detail": self.detail_in.text(),
            "standard": self.standard_in.text(),
            "frequency_days": self.freq_cb.currentData(),
            "notes": self.note_in.text(),
            "next_due_date": QDate.currentDate().toPyDate() # Default to today
        }

class ChecklistEditorDialog(QDialog):
    def __init__(self, plan, parent=None):
        super().__init__(parent)
        self.setWindowTitle(f"จัดการ Checklist: {plan.title}")
        self.setMinimumSize(600, 400)
        self.plan = plan
        from services import PMService
        self.svc = PMService()
        self._build_ui()
        self.refresh()

    def refresh(self):
        # Update UI with current items
        while self.items_lay.count():
            it = self.items_lay.takeAt(0)
            if it.widget(): it.widget().deleteLater()
            
        items = self.svc.db.query(models.PMChecklistItem).filter(models.PMChecklistItem.pm_plan_id == self.plan.id).order_by(models.PMChecklistItem.sequence).all()
        for i in items:
            row = QFrame()
            row.setStyleSheet(f"background: {ThemeManager.c('BG_CARD')}; border-radius: 4px; padding: 5px;")
            rl = QHBoxLayout(row)
            rl.addWidget(QLabel(f"{i.sequence}. {i.task_name}"))
            if i.standard:
                rl.addWidget(QLabel(f"(Std: {i.standard})"))
            if i.responsible_role:
                rl.addWidget(QLabel(f"[{i.responsible_role}]"))
            if i.is_parameter:
                rl.addWidget(QLabel(f"(Input: {i.parameter_unit})"))
            rl.addStretch()
            del_b = QPushButton("ลบ")
            del_b.setFixedSize(50, 25)
            del_b.clicked.connect(lambda _, item_id=i.id: self._remove_item(item_id))
            rl.addWidget(del_b)
            self.items_lay.addWidget(row)

    def _build_ui(self):
        main = QVBoxLayout(self)
        
        # Add Entry
        entry = QHBoxLayout()
        self.task_in = QLineEdit()
        self.task_in.setPlaceholderText("ระบุชื่องาน (เช่น ตรวจสอบสายพาน)")
        entry.addWidget(self.task_in, 2)
        
        self.std_in = QLineEdit()
        self.std_in.setPlaceholderText("มาตรฐาน (เช่น ไม่หย่อน)")
        entry.addWidget(self.std_in, 1)

        self.resp_in = QComboBox()
        self.resp_in.addItems(["พนักงาน", "หัวหน้า", "ช่างเทคนิค"])
        self.resp_in.setEditable(True)
        entry.addWidget(self.resp_in, 1)
        
        self.is_param = QCheckBox()
        self.is_param.setToolTip("เป็นค่าตัวเลข (Parameter)")
        entry.addWidget(self.is_param)
        
        self.unit_in = QLineEdit()
        self.unit_in.setPlaceholderText("หน่วย...")
        self.unit_in.setFixedWidth(80)
        entry.addWidget(self.unit_in)
        
        add_b = QPushButton("➕ เพิ่ม")
        add_b.setObjectName("btn_accent")
        add_b.clicked.connect(self._add_item)
        entry.addWidget(add_b)
        main.addLayout(entry)
        
        # List Area
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        container = QWidget()
        self.items_lay = QVBoxLayout(container)
        self.items_lay.setAlignment(Qt.AlignmentFlag.AlignTop)
        scroll.setWidget(container)
        main.addWidget(scroll)

    def _add_item(self):
        if not self.task_in.text(): return
        data = {
            "pm_plan_id": self.plan.id,
            "task_name": self.task_in.text(),
            "standard": self.std_in.text(),
            "responsible_role": self.resp_in.currentText(),
            "is_parameter": self.is_param.isChecked(),
            "parameter_unit": self.unit_in.text(),
            "sequence": self.svc.db.query(models.PMChecklistItem).filter(models.PMChecklistItem.pm_plan_id == self.plan.id).count() + 1
        }
        item = models.PMChecklistItem(**data)
        self.svc.db.add(item)
        self.svc.commit()
        self.task_in.clear()
        self.std_in.clear()
        self.unit_in.clear()
        self.is_param.setChecked(False)
        self.refresh()

    def _remove_item(self, iid):
        item = self.svc.db.query(models.PMChecklistItem).get(iid)
        if item:
            self.svc.db.delete(item)
            self.svc.commit()
            self.refresh()

# ─── Main Window ────────────────────────────────────────────────
class MainWindow(QMainWindow):
    NAV_ITEMS = [
        ("🏠", "หน้าหลัก (Dashboard)",    "dashboard"),
        ("⚡", "งานบำรุงรักษา (AM)",      "am_dashboard"),
        ("🔧", "ทะเบียนเครื่องจักร",       "registry"),
        ("🗺️", "เลย์เอาท์โรงงาน",         "layout"),
        ("📅", "แผนการบำรุงรักษา (PM)",   "pm"),
        ("🛠️", "แจ้งซ่อม (Repair)",       "repair"),
        ("📦", "คลังอะไหล่ (Inventory)",   "inventory"),
        ("📊", "วิเคราะห์ข้อมูล (Analytics)","analytics"),
        ("🛡️", "ใบอนุญาตงาน (Permit)",    "permit"),
        ("👥", "จัดการผู้ใช้งาน",         "users"),
        ("⚙",  "ตั้งค่าระบบ (Settings)",  "settings"),
        ("ℹ️",  "เกี่ยวกับโปรแกรม",         "about"),
    ]

    def __init__(self, user=None):
        super().__init__()
        self._current_user = user  # authenticated User object (or None)
        self.setWindowTitle("Maintenance Super App  v3.3")
        self.setMinimumSize(1280, 720)
        self.resize(1360, 780)
        self.setStyleSheet(ThemeManager.qss())
        # Set window icon (taskbar + title bar)
        _logo_p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "masapp_logo.png")
        if os.path.exists(_logo_p):
            from PyQt6.QtGui import QIcon
            self.setWindowIcon(QIcon(_logo_p))

        self._nav_buttons = {}
        self._active_key  = "registry"

        # Root layout: sidebar | content
        root_widget = QWidget()
        root_widget.setObjectName("root")
        root_widget.setStyleSheet(f"background: {BG_DARK};")
        root_layout = QHBoxLayout(root_widget)
        root_layout.setContentsMargins(0, 0, 0, 0)
        root_layout.setSpacing(0)

        root_layout.addWidget(self._build_sidebar())

        self.stack = QStackedWidget()
        self.stack.setObjectName("content_area")
        self._pages = {}
        self._add_pages()
        root_layout.addWidget(self.stack)

        self.setCentralWidget(root_widget)
        self._activate("registry")

    # ── Sidebar ────────────────────────────────────────────────
    def _build_sidebar(self):
        sidebar = QWidget()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(220)
        sl = QVBoxLayout(sidebar)
        sl.setContentsMargins(0, 0, 0, 0)
        sl.setSpacing(0)

        # ── Brand: logo + text
        brand_w = QWidget()
        brand_w.setStyleSheet("background: transparent;")
        brand_row = QHBoxLayout(brand_w)
        brand_row.setContentsMargins(16, 16, 16, 4)
        brand_row.setSpacing(8)
        _logo_p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "masapp_logo.png")
        logo_ico = QLabel()
        if os.path.exists(_logo_p):
            from PyQt6.QtGui import QPixmap
            _pix = QPixmap(_logo_p).scaledToHeight(32, Qt.TransformationMode.SmoothTransformation)
            logo_ico.setPixmap(_pix)
        else:
            logo_ico.setText("⚙")
            logo_ico.setFont(QFont("Segoe UI", 20))
        logo_ico.setStyleSheet("background: transparent;")
        brand = QLabel("MASAPP")
        brand.setObjectName("sidebar_brand")
        brand.setStyleSheet(
            f"font-size: 16px; font-weight: 700; color: {ACCENT_LIGHT};"
            f"background: transparent; letter-spacing: 2px;"
        )
        brand_row.addWidget(logo_ico)
        brand_row.addWidget(brand)
        brand_row.addStretch()
        ver = QLabel("  Maintenance Super App  v3.3")
        ver.setStyleSheet(
            f"font-size: 10px; color: {TEXT_MUTED}; padding: 0 16px 16px 16px;"
            f"background: transparent;"
        )
        sl.addWidget(brand_w)
        sl.addWidget(ver)
        sl.addWidget(make_separator())
        sl.addSpacing(6)

        for icon, label, key in self.NAV_ITEMS:
            # Role-based visibility
            if key in ["users", "settings"]:
                if not (self._current_user and self._current_user.role == "Admin"):
                    continue

            btn = QPushButton(f"  {icon}  {label}")
            btn.setObjectName("nav_btn")
            btn.setCursor(Qt.CursorShape.PointingHandCursor)
            btn.clicked.connect(lambda _, k=key: self._activate(k))
            self._nav_buttons[key] = btn
            sl.addWidget(btn)

        sl.addStretch()
        # ── Theme toggle + session bottom bar
        bottom_frame = QFrame()
        bottom_frame.setStyleSheet(
            f"background: {ThemeManager.c('BG_CARD')}; border-top: 1px solid {ThemeManager.c('BORDER')};"
        )
        bf_l = QVBoxLayout(bottom_frame)
        bf_l.setContentsMargins(14, 8, 14, 8)
        bf_l.setSpacing(4)

        # Theme toggle button
        t_icon  = ThemeManager.current()["icon"]
        t_name  = ThemeManager.current()["name"]
        next_name = THEMES["light"]["name"] if ThemeManager.current_key() == "dark" else THEMES["dark"]["name"]
        next_icon = THEMES["light"]["icon"]  if ThemeManager.current_key() == "dark" else THEMES["dark"]["icon"]
        theme_btn = QPushButton(f"{next_icon}  เปลี่ยนเป็น {next_name}")
        theme_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        theme_btn.setFixedHeight(30)
        theme_btn.setStyleSheet(
            f"background: transparent;"
            f"color: {ThemeManager.c('TEXT_MUTED')};"
            f"border: 1px solid {ThemeManager.c('BORDER')};"
            f"border-radius: 5px; font-size: 11px; padding: 2px 8px;"
        )
        theme_btn.clicked.connect(lambda: ThemeManager.toggle(self))
        bf_l.addWidget(theme_btn)

        # Session info
        u = self._current_user
        if u:
            meta       = ROLE_META.get(u.role, {"color": ThemeManager.c('TEXT_MUTED'), "label": u.role})
            role_color = meta["color"]
            display_name = u.full_name or u.username

            name_lbl = QLabel(f"👤  {display_name}")
            name_lbl.setStyleSheet(
                f"color: {ThemeManager.c('TEXT_PRIMARY')}; font-size: 12px; font-weight: 600; background: transparent;"
            )
            role_lbl = QLabel(f"● {u.role}")
            role_lbl.setStyleSheet(
                f"color: {role_color}; font-size: 11px; background: transparent;"
            )
            logout_btn = QPushButton("🚪  ออกจากระบบ")
            logout_btn.setObjectName("btn_secondary")
            logout_btn.setFixedHeight(28)
            logout_btn.setStyleSheet(
                f"background: transparent; color: {ThemeManager.c('RED')};"
                f"border: 1px solid {ThemeManager.c('RED')};"
                f"border-radius: 5px; font-size: 11px; padding: 2px 8px;"
            )
            logout_btn.clicked.connect(self._logout)
            bf_l.addWidget(name_lbl)
            bf_l.addWidget(role_lbl)
            bf_l.addWidget(logout_btn)
        else:
            guest = QLabel("👤  Guest")
            guest.setStyleSheet(
                f"color: {ThemeManager.c('TEXT_MUTED')}; font-size: 12px; background: transparent;"
            )
            bf_l.addWidget(guest)

        sl.addWidget(bottom_frame)
        return sidebar

    def _logout(self):
        reply = QMessageBox.question(
            self, "ออกจากระบบ", "ต้องการออกจากระบบใช่หรือไม่?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            self.close()
            dlg = LoginDialog()
            if dlg.exec() and dlg.authenticated_user:
                new_win = MainWindow(user=dlg.authenticated_user)
                new_win.show()
                self._next_window = new_win

    def _rebuild_sidebar(self):
        """Tear down old sidebar and replace with a freshly styled one."""
        # The sidebar is the first widget in the root horizontal layout
        root_layout = self.centralWidget().layout()
        old_sidebar = root_layout.itemAt(0).widget()
        new_sidebar  = self._build_sidebar()
        root_layout.replaceWidget(old_sidebar, new_sidebar)
        old_sidebar.deleteLater()
        # Re-activate current nav button so highlight colours update
        self._activate(self._active_key)

    # ── Pages ──────────────────────────────────────────────────
    def _add_pages(self):
        pages = {
            "dashboard":    placeholder_page("📊", "Dashboard", "กราฟ KPI และสรุปภาพรวม — กำลังพัฒนา"),
            "am_dashboard": AMDashboardPage(current_user=self._current_user),
            "registry":     MachineRegistryPage(current_user=self._current_user),
            "layout":    FactoryLayoutPage(current_user=self._current_user),
            "pm":        PMPlansPage(current_user=self._current_user),
            "repair":    placeholder_page("🛠️", "Repair Orders", "งานแจ้งซ่อมและวิเคราะห์ 5 Whys — กำลังพัฒนา"),
            "inventory": placeholder_page("📦", "Spare Parts", "ระบบคลังอะไหล่ — กำลังพัฒนา"),
            "analytics": placeholder_page("📈", "Analytics", "MTBF / MTTR / OEE / Pareto — กำลังพัฒนา"),
            "permit":    placeholder_page("🛡️", "E-Work Permit", "ระบบขออนุมัติงานซ่อมอันตราย — กำลังพัฒนา"),
            "users":     UserManagementPage(current_user=self._current_user),
            "settings":  SettingsPage(current_user=self._current_user),
            "about":     AboutPage(),
        }
        for key, widget in pages.items():
            self._pages[key] = widget
            self.stack.addWidget(widget)

    # ── Navigation ─────────────────────────────────────────────
    def _activate(self, key):
        if self._active_key and self._active_key in self._nav_buttons:
            self._nav_buttons[self._active_key].setObjectName("nav_btn")
            self._nav_buttons[self._active_key].setStyle(self._nav_buttons[self._active_key].style())
        self._active_key = key
        if key in self._nav_buttons:
            self._nav_buttons[key].setObjectName("nav_btn_active")
            self._nav_buttons[key].setStyle(self._nav_buttons[key].style())
        if key in self._pages:
            self.stack.setCurrentWidget(self._pages[key])
