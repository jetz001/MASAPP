from PyQt6.QtWidgets import (
    QGraphicsView, QGraphicsScene, QGraphicsPixmapItem, QGraphicsItem,
    QGraphicsEllipseItem, QWidget, QVBoxLayout, QHBoxLayout, QLabel, 
    QPushButton, QComboBox, QFileDialog, QMessageBox, QFrame, QMenu,
    QGraphicsSceneMouseEvent, QToolTip, QLineEdit, QListWidget, QListWidgetItem
)
from PyQt6.QtCore import Qt, QPointF, pyqtSignal, QRectF
from PyQt6.QtGui import QPixmap, QColor, QFont, QPen, QBrush, QAction, QTransform, QPainter
import os

from services import FactoryMapService, MachineService, UserService, ROLE_ADMIN, ROLE_ENGINEER, ROLE_MANAGER
from models import Machine, FactoryMap

class MachinePinItem(QGraphicsEllipseItem):
    clicked = pyqtSignal(int) # Emits machine_id

    def __init__(self, machine, x, y, scale_factor=1.0):
        # Base size is say 20x20
        size = 20 / scale_factor
        super().__init__(-size/2, -size/2, size, size)
        
        self.machine = machine
        self.machine_id = machine.id
        self.setPos(x, y)
        
        from views import ThemeManager
        
        # Real status logic mapping
        raw_status = getattr(machine, 'status', 'Running') or 'Running'
        if raw_status == 'Running':
            color = ThemeManager.c('ACCENT_LIGHT')
            self.status = "🟢 ปกติ"
        elif raw_status == 'Warning':
            color = ThemeManager.c('YELLOW')
            self.status = "🟡 แจ้งเตือน"
        elif raw_status == 'Breakdown':
            color = ThemeManager.c('RED')
            self.status = "🔴 ขัดข้อง"
        else:
            color = ThemeManager.c('TEXT_MUTED')
            self.status = raw_status
        
        self.setBrush(QBrush(QColor(color)))
        self.setPen(QPen(QColor(ThemeManager.c('BG_CARD')), 2 / scale_factor))
        self.setAcceptHoverEvents(True)
        self.setCursor(Qt.CursorShape.PointingHandCursor)
        self.setZValue(10) # Ensure pins are above the map
        self.scale_factor = scale_factor
        
        # We can't use pyqtSignal directly on QGraphicsItem easily, so we handle it in scene/view or manually route
        
    def hoverEnterEvent(self, event):
        super().hoverEnterEvent(event)
        # Show tooltip
        tooltip_text = f"<b>{self.machine.name}</b> ({self.machine.code})<br/>Status: <b>{self.status}</b>"
        QToolTip.showText(event.screenPos(), tooltip_text)
        
        # Grow slightly on hover
        self.setScale(1.2)

    def hoverLeaveEvent(self, event):
        super().hoverLeaveEvent(event)
        QToolTip.hideText()
        self.setScale(1.0)
        
    def mousePressEvent(self, event):
        # We'll let the scene/view handle the click routing for simplicity, 
        # or we can pass a callback
        super().mousePressEvent(event)

class InteractiveMapView(QGraphicsView):
    pin_clicked = pyqtSignal(int)     # emit machine_id
    map_clicked = pyqtSignal(QPointF) # emit coordinates for pinning

    def __init__(self, parent=None):
        super().__init__(parent)
        self.scene = QGraphicsScene(self)
        self.setScene(self.scene)
        self.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform)
        self.setDragMode(QGraphicsView.DragMode.ScrollHandDrag)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        
        self._zoom = 0
        self.map_item = None
        self.pins = []
        self.setup_mode = False

        self.setStyleSheet("background: transparent; border: none;")

    def set_map(self, image_path):
        self.scene.clear()
        self.pins.clear()
        self.map_item = None
        
        if not os.path.exists(image_path):
            return False
            
        pixmap = QPixmap(image_path)
        if pixmap.isNull():
            return False
            
        self.map_item = QGraphicsPixmapItem(pixmap)
        self.scene.addItem(self.map_item)
        self.setSceneRect(QRectF(pixmap.rect()))
        
        # Fit to view initially
        self.fitInView(self.sceneRect(), Qt.AspectRatioMode.KeepAspectRatio)
        self._zoom = 0
        return True

    def add_pin(self, machine, x, y):
        # Calculate current scale to size pins consistently
        transform = self.transform()
        scale_factor = transform.m11()
        if scale_factor == 0: scale_factor = 1.0
        
        pin = MachinePinItem(machine, x, y, scale_factor=scale_factor)
        self.scene.addItem(pin)
        self.pins.append(pin)

    def wheelEvent(self, event):
        if self.hasPhoto():
            if event.angleDelta().y() > 0:
                factor = 1.25
                self._zoom += 1
            else:
                factor = 0.8
                self._zoom -= 1
            if self._zoom > 0:
                self.scale(factor, factor)
                self._rescale_pins()
            elif self._zoom == 0:
                self.fitInView(self.sceneRect(), Qt.AspectRatioMode.KeepAspectRatio)
                self._rescale_pins()
            else:
                self._zoom = 0

    def hasPhoto(self):
        return self.map_item is not None

    def _rescale_pins(self):
        # Keep pins visually same size regardless of zoom
        transform = self.transform()
        scale_factor = transform.m11()
        if scale_factor == 0: scale_factor = 1.0
        
        from views import ThemeManager
        for pin in self.pins:
            size = 20 / scale_factor
            pin.setRect(-size/2, -size/2, size, size)
            pin.setPen(QPen(QColor(ThemeManager.c('BG_CARD')), 2 / scale_factor))

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            item = self.itemAt(event.pos())
            if isinstance(item, MachinePinItem):
                self.pin_clicked.emit(item.machine_id)
                # Call base class so hover events properly reset if needed
                super().mousePressEvent(event)
                return
            elif self.setup_mode and self.hasPhoto():
                # Get scene coordinates
                pos = self.mapToScene(event.pos())
                self.map_clicked.emit(pos)
                
        # Call base implementation to allow panning
        super().mousePressEvent(event)


class FactoryLayoutPage(QWidget):
    def __init__(self, current_user=None):
        super().__init__()
        self.current_user = current_user
        self.map_service = FactoryMapService()
        self.machine_service = MachineService()
        if self.current_user:
            self.map_service.set_current_user(self.current_user)
            self.machine_service.set_current_user(self.current_user)
        
        self.current_map_id = None
        self.setup_mode = False
        self.filter_abnormal_only = False
        
        self._build_ui()
        self.load_maps()

    def _build_ui(self):
        from views import ThemeManager, make_label, make_separator
        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 16, 24, 24)
        layout.setSpacing(12)

        # -- Top Bar --
        top_row = QHBoxLayout()
        top_row.addWidget(make_label("แผนผังโรงงาน (Factory Layout)", 18, bold=True))
        
        self.map_selector = QComboBox()
        self.map_selector.setFixedWidth(250)
        self.map_selector.currentIndexChanged.connect(self._on_map_changed)
        self.map_selector.setStyleSheet(f"background: {ThemeManager.c('BG_CARD')}; color: {ThemeManager.c('TEXT_PRIMARY')}; padding: 6px; border: 1px solid {ThemeManager.c('BORDER')}; border-radius: 4px;")
        top_row.addWidget(make_label("  ชั้น/อาคาร: ", 12))
        top_row.addWidget(self.map_selector)
        
        top_row.addStretch()

        # Tools
        self.btn_filter = QPushButton(" กรอง: ทั้งหมด ")
        self.btn_filter.setObjectName("btn_secondary")
        self.btn_filter.clicked.connect(self._toggle_filter)
        top_row.addWidget(self.btn_filter)

        if self.current_user and self.current_user.role in [ROLE_ADMIN, ROLE_ENGINEER, ROLE_MANAGER]:
            self.btn_setup = QPushButton(" ⚙️ วางเครื่องจักร ")
            self.btn_setup.setObjectName("btn_secondary")
            self.btn_setup.clicked.connect(self._toggle_setup_mode)
            top_row.addWidget(self.btn_setup)
            
            self.btn_upload = QPushButton("อัปโหลดแปลนใหม่")
            self.btn_upload.setObjectName("btn_primary")
            self.btn_upload.clicked.connect(self._upload_map)
            top_row.addWidget(self.btn_upload)
            
            self.btn_reset = QPushButton("รีเซ็ตพิกัด")
            self.btn_reset.setObjectName("btn_danger")
            self.btn_reset.clicked.connect(self._reset_pins)
            top_row.addWidget(self.btn_reset)

        layout.addLayout(top_row)
        layout.addWidget(make_separator())

        # -- Map Canvas Area --
        self.map_view = InteractiveMapView()
        self.map_view.pin_clicked.connect(self._on_pin_clicked)
        self.map_view.map_clicked.connect(self._on_map_clicked)
        
        # Floating Legend overlaying the map view
        legend_frame = QFrame(self.map_view)
        legend_frame.setObjectName("card")
        legend_frame.setStyleSheet(f"background: {ThemeManager.c('BG_CARD')}DD; border-radius: 6px; padding: 2px;")
        ll = QHBoxLayout(legend_frame)
        ll.setContentsMargins(12, 6, 12, 6)
        ll.setSpacing(12)
        ll.addWidget(make_label("🟢 ปกติ", 11, bold=True))
        ll.addWidget(make_label("🟡 แจ้งเตือน", 11, bold=True))
        ll.addWidget(make_label("🔴 ขัดข้อง", 11, bold=True))
        legend_frame.move(16, 16)
        
        map_container = QFrame()
        map_container.setObjectName("card")
        map_layout = QVBoxLayout(map_container)
        map_layout.setContentsMargins(2, 2, 2, 2)
        map_layout.addWidget(self.map_view)
        
        layout.addWidget(map_container, 1)

    def load_maps(self):
        self.map_selector.blockSignals(True)
        self.map_selector.clear()
        maps = self.map_service.get_all_maps()
        for m in maps:
            self.map_selector.addItem(m.name, m.id)
            
        self.map_selector.blockSignals(False)
        
        if maps:
            self.current_map_id = maps[0].id
            self._load_current_map()
        else:
            self.map_view.scene.clear()
            self.map_view.scene.addText("ยังไม่ได้อัปโหลดแผนผังโรงงาน...", QFont("Segoe UI", 16))

    def _on_map_changed(self):
        map_id = self.map_selector.currentData()
        if map_id is not None:
            self.current_map_id = map_id
            self._load_current_map()

    def _load_current_map(self):
        if not self.current_map_id: return
        map_model = self.map_service.get_map_by_id(self.current_map_id)
        if not map_model: return
        
        success = self.map_view.set_map(map_model.image_path)
        if not success:
            QMessageBox.warning(self, "พบปัญหา", f"ไม่สามารถโหลดไฟล์รูปภาพ {map_model.image_path} ได้")
            return
            
        self._load_pins()

    def _load_pins(self):
        if not self.current_map_id: return
        
        # Remove old pins
        for pin in self.map_view.pins:
            self.map_view.scene.removeItem(pin)
        self.map_view.pins.clear()
        
        machines = self.machine_service.get_all_machines()
        for m in machines:
            if m.map_id == self.current_map_id and m.map_x is not None and m.map_y is not None:
                # Apply filter logic
                raw_status = getattr(m, 'status', 'Running') or 'Running'
                if self.filter_abnormal_only and raw_status == 'Running':
                    continue
                    
                self.map_view.add_pin(m, m.map_x, m.map_y)

    def _toggle_setup_mode(self):
        from views import ThemeManager
        self.setup_mode = not self.setup_mode
        self.map_view.setup_mode = self.setup_mode
        if self.setup_mode:
            self.btn_setup.setText(" 🔒 ยกเลิกการวาง ")
            self.btn_setup.setStyleSheet(f"background: {ThemeManager.c('BLUE')}; color: white; padding: 6px 16px; border-radius: 4px;")
        else:
            self.btn_setup.setText(" ⚙️ วางเครื่องจักร ")
            self.btn_setup.setStyleSheet("")
            self.btn_setup.setObjectName("btn_secondary")
            self.btn_setup.setStyle(self.btn_setup.style())

    def _toggle_filter(self):
        from views import ThemeManager
        self.filter_abnormal_only = not self.filter_abnormal_only
        if self.filter_abnormal_only:
            self.btn_filter.setText(" กรอง: เฉพาะที่มีปัญหา ")
            self.btn_filter.setStyleSheet(f"background: {ThemeManager.c('RED')}; color: white; padding: 6px 16px; border-radius: 4px;")
        else:
            self.btn_filter.setText(" กรอง: ทั้งหมด ")
            self.btn_filter.setStyleSheet("")
            self.btn_filter.setObjectName("btn_secondary")
            self.btn_filter.setStyle(self.btn_filter.style())
        self._load_pins()

    def _upload_map(self):
        from PyQt6.QtWidgets import QInputDialog
        
        file_path, _ = QFileDialog.getOpenFileName(self, "เลือกไฟล์แปลนโรงงาน (แผนที่ 2D)", "", "Images (*.png *.jpg *.jpeg)")
        if not file_path: return
        
        name, ok = QInputDialog.getText(self, "ชื่อแผนผัง", "กรุณาระบุชื่อชั้น หรือพื้นที่ (เช่น อาคาร A - ชั้น 1):")
        if not ok or not name.strip(): return
        
        # Copy file to assets
        import shutil
        dest_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "maps")
        if not os.path.exists(dest_dir):
            os.makedirs(dest_dir)
            
        ext = os.path.splitext(file_path)[1]
        import time
        safe_name = f"map_{int(time.time())}{ext}"
        dest_path = os.path.join(dest_dir, safe_name)
        
        shutil.copy2(file_path, dest_path)
        
        try:
            self.map_service.create_map(name.strip(), dest_path)
            self.load_maps()
            QMessageBox.information(self, "สำเร็จ", "อัปโหลดแผนผังเรียบร้อยแล้ว")
        except Exception as e:
            QMessageBox.critical(self, "ข้อผิดพลาด", f"ไม่สามารถบันทึกได้:\n{str(e)}")

    def _on_map_clicked(self, pos: QPointF):
        if not self.setup_mode or not self.current_map_id: return
        
        # Open dialog to select machine
        from PyQt6.QtWidgets import QDialog, QListWidget, QDialogButtonBox
        
        dlg = QDialog(self)
        dlg.setWindowTitle("เลือกเครื่องจักรเพื่อปักหมุด")
        dlg.resize(400, 500)
        dl = QVBoxLayout(dlg)
        
        search = QLineEdit()
        search.setPlaceholderText("ค้นหาเครื่องจักร...")
        dl.addWidget(search)
        
        list_w = QListWidget()
        dl.addWidget(list_w)
        
        # Load all unpinned machines (or all machines if you prefer letting them move pins)
        machines = self.machine_service.get_all_machines()
        def update_list(filter_text=""):
            list_w.clear()
            for m in machines:
                if filter_text.lower() in m.name.lower() or filter_text.lower() in m.code.lower():
                    # Show indicator if already pinned on this map
                    mark = "📌 " if m.map_id == self.current_map_id else ""
                    item = QListWidgetItem(f"{mark}{m.code} - {m.name}")
                    item.setData(Qt.ItemDataRole.UserRole, m.id)
                    list_w.addItem(item)
                    
        search.textChanged.connect(update_list)
        update_list()
        
        bbox = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        bbox.accepted.connect(dlg.accept)
        bbox.rejected.connect(dlg.reject)
        dl.addWidget(bbox)
        
        if dlg.exec() == QDialog.DialogCode.Accepted:
            selected = list_w.currentItem()
            if selected:
                machine_id = selected.data(Qt.ItemDataRole.UserRole)
                # Update DB
                self._update_machine_location(machine_id, self.current_map_id, pos.x(), pos.y())
                # Reload pins
                self._load_pins()

    def _update_machine_location(self, machine_id, map_id, x, y):
        # We need to add update_location to MachineService
        # Let's do it directly through service.db for brevity since we're in the same layer
        # But properly we should use the service.
        m = self.machine_service.db.query(Machine).filter(Machine.id == machine_id).first()
        if m:
            m.map_id = map_id
            m.map_x = x
            m.map_y = y
            self.machine_service.db.commit()
            
    def _on_pin_clicked(self, machine_id):
        # Open machine dashboard / view dialog
        print(f"Pin clicked for machine {machine_id}")
        # In actual implementation:
        from views import ViewMachineDialog
        m = self.machine_service.get_machine(machine_id)
        if m:
            dlg = ViewMachineDialog(m, self)
            dlg.exec()

    def _reset_pins(self):
        if not self.current_map_id: return
        reply = QMessageBox.question(self, "ยืนยันการล้างพิกัด", "ต้องการรีเซ็ตพิกัดเครื่องจักรทั้งหมดบนแผนผังนี้หรือไม่?", QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        if reply == QMessageBox.StandardButton.Yes:
            machines = self.machine_service.db.query(Machine).filter(Machine.map_id == self.current_map_id).all()
            for m in machines:
                m.map_id = None
                m.map_x = None
                m.map_y = None
            self.machine_service.db.commit()
            self._load_pins()
            QMessageBox.information(self, "สำเร็จ", "รีเซ็ตพิกัดเรียบร้อยแล้ว")
