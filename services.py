from models import SessionLocal, User, AuditLog
import hashlib
import shutil, os
from datetime import datetime
from utils import config

# ─────────────────────────────────────────────────────────────
#  RBAC  –  4 Roles × 4 Actions × N Resources
# ─────────────────────────────────────────────────────────────
#  Roles:
#    Admin      – ผู้ดูแลระบบ (Admin)
#    Manager    – ผู้จัดการ / ผู้บริหาร
#    Technician – ช่างเทคนิค
#    Viewer     – ผู้ดูข้อมูลเท่านั้น
#
#  Actions:   create | read | update | approve | delete
#
#  Resources: machine | work_order | pm_plan | spare_part
#             work_permit | user | audit_log
# ─────────────────────────────────────────────────────────────

ROLE_ADMIN      = "Admin"
ROLE_MANAGER    = "Manager"
ROLE_ENGINEER   = "Engineer"
ROLE_TECHNICIAN = "Technician"
ROLE_VIEWER     = "Viewer"

ALL_ROLES = [ROLE_ADMIN, ROLE_MANAGER, ROLE_ENGINEER, ROLE_TECHNICIAN, ROLE_VIEWER]

# ─── Permission Matrix ─────────────────────────────────────────
# Structure: PERMISSIONS[role][resource] = set of allowed actions
PERMISSIONS = {
    ROLE_ADMIN: {
        "machine":      {"create", "read", "update", "approve", "delete"},
        "work_order":   {"create", "read", "update", "approve", "delete"},
        "pm_plan":      {"create", "read", "update", "approve", "delete"},
        "spare_part":   {"create", "read", "update", "approve", "delete"},
        "work_permit":  {"create", "read", "update", "approve", "delete"},
        "user":         {"create", "read", "update", "approve", "delete"},
        "audit_log":    {"read"},
    },
    ROLE_MANAGER: {
        "machine":      {"create", "read", "update", "approve"},
        "work_order":   {"create", "read", "update", "approve"},
        "pm_plan":      {"create", "read", "update", "approve"},
        "spare_part":   {"create", "read", "update", "approve"},
        "work_permit":  {"read", "update", "approve"},
        "user":         {"read"},
        "audit_log":    {"read"},
    },
    ROLE_ENGINEER: {
        "machine":      {"create", "read", "update", "approve"},
        "work_order":   {"create", "read", "update", "approve"},
        "pm_plan":      {"create", "read", "update", "approve"},
        "spare_part":   {"create", "read", "update"},
        "work_permit":  {"create", "read", "update", "approve"},
        "user":         {"read"},
        "audit_log":    {"read"},
    },
    ROLE_TECHNICIAN: {
        "machine":      {"create", "read", "update"},
        "work_order":   {"create", "read", "update"},
        "pm_plan":      {"create", "read", "update"},
        "spare_part":   {"read", "update"},
        "work_permit":  {"create", "read"},
        "user":         set(),
        "audit_log":    set(),
    },
    ROLE_VIEWER: {
        "machine":      {"read"},
        "work_order":   {"read"},
        "pm_plan":      {"read"},
        "spare_part":   {"read"},
        "work_permit":  {"read"},
        "user":         set(),
        "audit_log":    set(),
    },
}

ROLE_META = {
    ROLE_ADMIN:      {"label": "Admin (ผู้ดูแลระบบ)",      "color": "#F85149", "desc": "เข้าถึงได้ทุกฟังก์ชัน ลบข้อมูลได้"},
    ROLE_MANAGER:    {"label": "Manager (ผู้จัดการ)",       "color": "#D29922", "desc": "สร้าง อัปเดต อนุมัติ ไม่สามารถลบได้"},
    ROLE_ENGINEER:   {"label": "Engineer (วิศวกร)",         "color": "#BF91F3", "desc": "อนุมัติ PM ใบอนุญาต และงานซ่อม ไม่สามารถลบได้"},
    ROLE_TECHNICIAN: {"label": "Technician (ช่างเทคนิค)",  "color": "#388BFD", "desc": "สร้างและอัปเดต ไม่สามารถอนุมัติได้"},
    ROLE_VIEWER:     {"label": "Viewer (ผู้ดูข้อมูล)",      "color": "#8B949E", "desc": "ดูข้อมูลได้อย่างเดียว"},
}


def can(role: str, resource: str, action: str) -> bool:
    """Check if a role is allowed to perform action on resource."""
    return action in PERMISSIONS.get(role, {}).get(resource, set())


# ─────────────────────────────────────────────────────────────
#  Base Service
# ─────────────────────────────────────────────────────────────
class BaseService:
    def __init__(self):
        self.db = SessionLocal()
        self.current_user_id = None
        self.current_role = ROLE_VIEWER

    def set_current_user(self, user: User):
        self.current_user_id = user.id
        self.current_role = user.role

    def can(self, resource: str, action: str) -> bool:
        return can(self.current_role, resource, action)

    def require(self, resource: str, action: str):
        if not self.can(resource, action):
            raise PermissionError(
                f"สิทธิ์ไม่เพียงพอ: บทบาท '{self.current_role}' ไม่สามารถ '{action}' บน '{resource}' ได้"
            )

    def log_audit(self, action, table_name, record_id, details=""):
        log = AuditLog(
            user_id=self.current_user_id,
            action=action,
            table_name=table_name,
            record_id=record_id,
            details=details,
            ip_address="127.0.0.1"
        )
        self.db.add(log)

    def commit(self):
        try:
            self.db.commit()
        except Exception as e:
            self.db.rollback()
            raise e

    def close(self):
        self.db.close()


# ─────────────────────────────────────────────────────────────
#  User Service
# ─────────────────────────────────────────────────────────────
class UserService(BaseService):
    @staticmethod
    def hash_password(password: str) -> str:
        return hashlib.sha256(password.encode()).hexdigest()

    def login(self, username: str, password: str):
        user = self.db.query(User).filter(User.username == username).first()
        if user and user.password_hash == self.hash_password(password) and user.is_active:
            self.set_current_user(user)
            self.log_audit("LOGIN", "users", user.id, "User logged in")
            self.commit()
            return user
        return None

    def get_all_users(self):
        return self.db.query(User).all()

    def create_user(self, username: str, password: str, role: str,
                    full_name: str, requester_role: str = ROLE_ADMIN):
        if requester_role not in [ROLE_ADMIN]:
            raise PermissionError("เฉพาะ Admin เท่านั้นที่สามารถสร้างผู้ใช้งานได้")
        user = User(
            username=username,
            password_hash=self.hash_password(password),
            role=role,
            full_name=full_name
        )
        self.db.add(user)
        self.commit()
        self.log_audit("CREATE", "users", user.id, f"สร้างผู้ใช้ {username} บทบาท {role}")
        self.commit()
        return user

    def update_user(self, user_id: int, full_name: str = None,
                     role: str = None, is_active: bool = None):
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            raise ValueError("ไม่พบผู้ใช้งาน")
        changes = []
        if full_name is not None:
            user.full_name = full_name
            changes.append(f"name={full_name}")
        if role is not None:
            user.role = role
            changes.append(f"role={role}")
        if is_active is not None:
            user.is_active = is_active
            changes.append(f"active={is_active}")
        self.log_audit("UPDATE", "users", user.id, ", ".join(changes))
        self.commit()
        return user

    def reset_password(self, user_id: int, new_password: str):
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            raise ValueError("ไม่พบผู้ใช้งาน")
        user.password_hash = self.hash_password(new_password)
        self.log_audit("RESET_PW", "users", user.id, "รีเซ็ตรหัสผ่าน")
        self.commit()

    def delete_user(self, user_id: int):
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            raise ValueError("ไม่พบผู้ใช้งาน")
        username = user.username
        self.db.delete(user)
        self.log_audit("DELETE", "users", user_id, f"ลบผู้ใช้ {username}")
        self.commit()

# ─────────────────────────────────────────────────────────────
#  Factory Map Service (Layouts)
# ─────────────────────────────────────────────────────────────
class FactoryMapService(BaseService):
    def get_all_maps(self):
        from models import FactoryMap
        return self.db.query(FactoryMap).order_by(FactoryMap.id.asc()).all()
    
    def get_map_by_id(self, map_id: int):
        from models import FactoryMap
        return self.db.query(FactoryMap).filter(FactoryMap.id == map_id).first()
        
    def create_map(self, name: str, image_path: str):
        self.require("machine", "create") # Using machine creation role
        from models import FactoryMap
        new_map = FactoryMap(
            name=name,
            image_path=image_path
        )
        self.db.add(new_map)
        self.db.commit()
        self.db.refresh(new_map)
        self.log_audit("create", "factory_maps", new_map.id, f"Uploaded map: {name}")
        return new_map
        
    def delete_map(self, map_id: int):
        self.require("machine", "delete")
        from models import FactoryMap, Machine
        m = self.db.query(FactoryMap).filter(FactoryMap.id == map_id).first()
        if not m:
            raise ValueError("Map not found")
            
        # Clear pins linked to this map
        machines = self.db.query(Machine).filter(Machine.map_id == map_id).all()
        for mach in machines:
            mach.map_id = None
            mach.map_x = None
            mach.map_y = None
            
        try:
            if os.path.exists(m.image_path):
                os.remove(m.image_path)
        except:
             pass
             
        self.db.delete(m)
        self.log_audit("delete", "factory_maps", map_id, f"Deleted map: {m.name}")
        self.commit()


# ─────────────────────────────────────────────────────────────
#  System Service (Backup)
# ─────────────────────────────────────────────────────────────
class SystemService(BaseService):
    def backup_database(self):
        db_url = config.get('Database', 'url')
        if db_url.startswith('sqlite:///'):
            db_path = db_url.replace('sqlite:///', '')
            backup_dir = config.get('General', 'backup_dir', fallback='./backups')
            os.makedirs(backup_dir, exist_ok=True)
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_file = os.path.join(backup_dir, f"masapp_backup_{timestamp}.db")
            try:
                shutil.copy2(db_path, backup_file)
                self.log_audit("BACKUP", "system", 0, f"สำรองข้อมูลที่ {backup_file}")
                self.commit()
                return True, backup_file
            except Exception as e:
                return False, str(e)
        return False, "รองรับเฉพาะ SQLite ในรูปแบบนี้"


# ─────────────────────────────────────────────────────────────
#  Machine Service
# ─────────────────────────────────────────────────────────────
import qrcode
from models import Machine, MachineAttachment, MachineIntakeForm


class MachineService(BaseService):
    def add_machine(self, code, name, model, serial_number, installation_date, zone,
                    **kwargs):
        machine = Machine(
            code=code, name=name, model=model,
            serial_number=serial_number,
            installation_date=installation_date, zone=zone,
            **kwargs
        )
        self.db.add(machine)
        self.commit()
        self.log_audit("CREATE", "machines", machine.id, f"เพิ่มเครื่องจักร {code}")
        self.commit()
        return machine

    def get_all_machines(self):
        return self.db.query(Machine).all()

    def get_machine(self, machine_id: int):
        return self.db.query(Machine).filter(Machine.id == machine_id).first()

    def update_machine(self, machine_id: int, **kwargs):
        m = self.db.query(Machine).filter(Machine.id == machine_id).first()
        if not m:
            raise ValueError("ไม่พบเครื่องจักร")
        for k, v in kwargs.items():
            if hasattr(m, k):
                setattr(m, k, v)
        self.log_audit("UPDATE", "machines", machine_id, str(kwargs))
        self.commit()
        return m

    def delete_machine(self, machine_id: int):
        m = self.db.query(Machine).filter(Machine.id == machine_id).first()
        if not m:
            raise ValueError("ไม่พบเครื่องจักร")
        code = m.code
        self.db.delete(m)
        self.log_audit("DELETE", "machines", machine_id, f"ลบเครื่องจักร {code}")
        self.commit()

    def generate_qr(self, machine_code):
        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(f"MACHINE:{machine_code}")
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")
        qr_dir = os.path.join("assets", "qrcodes")
        os.makedirs(qr_dir, exist_ok=True)
        filepath = os.path.join(qr_dir, f"{machine_code}.png")
        img.save(filepath)
        return filepath

    def add_attachment(self, machine_id, file_path, file_type):
        dest_dir = os.path.join("assets", "attachments", str(machine_id))
        os.makedirs(dest_dir, exist_ok=True)
        filename = os.path.basename(file_path)
        dest_path = os.path.join(dest_dir, filename)
        shutil.copy2(file_path, dest_path)
        attachment = MachineAttachment(
            machine_id=machine_id, file_path=dest_path, file_type=file_type
        )
        self.db.add(attachment)
        self.log_audit("ATTACH", "machine_attachments", attachment.id, f"แนบ {file_type}")
        self.commit()
        return attachment


# ─────────────────────────────────────────────────────────────
#  Intake Form Service  –  ใบรับเครื่องจักร
# ─────────────────────────────────────────────────────────────
class IntakeFormService(BaseService):
    """Manages the MachineIntakeForm pre-approval workflow."""

    # statuses
    DRAFT    = "Draft"
    PENDING  = "Pending"
    APPROVED = "Approved"
    REJECTED = "Rejected"

    # roles that CAN approve
    APPROVER_ROLES = {ROLE_ADMIN, ROLE_MANAGER}
    # roles that CAN submit (all except Viewer)
    SUBMITTER_ROLES = {ROLE_ADMIN, ROLE_MANAGER, ROLE_ENGINEER, ROLE_TECHNICIAN}

    def _next_form_number(self) -> str:
        import datetime as dt
        year = dt.datetime.now().year
        count = self.db.query(MachineIntakeForm).count() + 1
        return f"MR-{year}-{count:04d}"

    # ── CRUD ────────────────────────────────────────────────────
    def create_form(self, data: dict, submitted_by_id: int = None) -> MachineIntakeForm:
        """Create a new Draft intake form."""
        form = MachineIntakeForm(
            form_number    = self._next_form_number(),
            submitted_by_id= submitted_by_id,
            status         = self.DRAFT,
            **{k: v for k, v in data.items() if hasattr(MachineIntakeForm, k)}
        )
        self.db.add(form)
        self.commit()
        self.log_audit("CREATE", "machine_intake_forms", form.id,
                       f"สร้างใบรับ {form.form_number}")
        self.commit()
        return form

    def update_form(self, form_id: int, data: dict) -> MachineIntakeForm:
        form = self._get_or_raise(form_id)
        if form.status not in (self.DRAFT, self.REJECTED):
            raise ValueError("แก้ไขได้เฉพาะ Draft หรือ Rejected เท่านั้น")
        for k, v in data.items():
            if hasattr(form, k):
                setattr(form, k, v)
        self.log_audit("UPDATE", "machine_intake_forms", form_id, "อัปเดตใบรับ")
        self.commit()
        return form

    def get_form(self, form_id: int) -> MachineIntakeForm:
        return self._get_or_raise(form_id)

    def get_all_forms(self):
        return (self.db.query(MachineIntakeForm)
                .order_by(MachineIntakeForm.created_at.desc())
                .all())

    def get_pending_forms(self):
        return (self.db.query(MachineIntakeForm)
                .filter(MachineIntakeForm.status == self.PENDING)
                .order_by(MachineIntakeForm.submitted_at)
                .all())

    def delete_form(self, form_id: int):
        form = self._get_or_raise(form_id)
        self.db.delete(form)
        self.log_audit("DELETE", "machine_intake_forms", form_id, f"ลบใบรับ {form.form_number}")
        self.commit()

    # ── Workflow ────────────────────────────────────────────────
    def submit_for_approval(self, form_id: int, requester_role: str):
        """Draft → Pending. Any role except Viewer."""
        if requester_role == ROLE_VIEWER:
            raise PermissionError("Viewer ไม่สามารถส่งขออนุมัติได้")
        form = self._get_or_raise(form_id)
        if form.status not in (self.DRAFT, self.REJECTED):
            raise ValueError(f"ไม่สามารถส่งได้ — สถานะปัจจุบัน: {form.status}")
        import datetime as dt
        form.status      = self.PENDING
        form.submitted_at= dt.datetime.now()
        self.log_audit("SUBMIT", "machine_intake_forms", form_id,
                       f"ส่งขออนุมัติ {form.form_number}")
        self.commit()
        return form

    def approve_form(self, form_id: int, approver_id: int,
                     approver_role: str) -> Machine:
        """Pending → Approved + creates Machine in registry."""
        if approver_role not in self.APPROVER_ROLES:
            raise PermissionError("เฉพาะ Manager หรือ Admin เท่านั้นที่อนุมัติได้")
        form = self._get_or_raise(form_id)
        if form.status != self.PENDING:
            raise ValueError(f"ต้องเป็นสถานะ Pending — ปัจจุบัน: {form.status}")

        import datetime as dt
        form.status      = self.APPROVED
        form.approved_by_id = approver_id
        form.approved_at = dt.datetime.now()

        # ── Create Machine record ──────────────────────────────
        machine = Machine(
            code          = form.code,
            name          = form.name,
            model         = form.model,
            serial_number = form.serial_number,
            installation_date = form.installation_date,
            zone          = form.zone,
            power_kw      = form.power_kw,
            voltage_v     = form.voltage_v,
            current_amp   = form.current_amp,
            phase         = form.phase,
            dimensions    = form.dimensions,
            weight_kg     = form.weight_kg,
            supplier_name = form.supplier_name,
            supplier_contact = form.supplier_contact,
            supplier_sales= form.supplier_sales,
            warranty_months  = form.warranty_months,
            has_manual    = form.has_manual,
            manual_file_path = form.manual_file_path,
            training_done = form.training_done,
            intake_form_id= form.id,
            status        = "Running",
        )
        self.db.add(machine)
        self.log_audit("APPROVE", "machine_intake_forms", form_id,
                       f"อนุมัติ {form.form_number} → สร้างเครื่องจักร {form.code}")
        self.commit()
        return machine

    def reject_form(self, form_id: int, approver_id: int,
                    approver_role: str, reason: str = ""):
        """Pending → Rejected."""
        if approver_role not in self.APPROVER_ROLES:
            raise PermissionError("เฉพาะ Manager หรือ Admin เท่านั้นที่ปฏิเสธได้")
        form = self._get_or_raise(form_id)
        if form.status != self.PENDING:
            raise ValueError(f"ต้องเป็นสถานะ Pending — ปัจจุบัน: {form.status}")
        form.status      = self.REJECTED
        form.reject_reason = reason
        self.log_audit("REJECT", "machine_intake_forms", form_id,
                       f"ปฏิเสธ {form.form_number}: {reason}")
        self.commit()
        return form

    # ── Helpers ─────────────────────────────────────────────────
    def _get_or_raise(self, form_id: int) -> MachineIntakeForm:
        form = self.db.query(MachineIntakeForm).filter(
            MachineIntakeForm.id == form_id).first()
        if not form:
            raise ValueError(f"ไม่พบใบรับ ID={form_id}")
        return form

    def copy_file_to_assets(self, src_path: str, subfolder: str) -> str:
        """Copy a PDF/doc to assets folder and return stored path."""
        dest_dir = os.path.join("assets", "intake_docs", subfolder)
        os.makedirs(dest_dir, exist_ok=True)
        filename = os.path.basename(src_path)
        dest = os.path.join(dest_dir, filename)
        shutil.copy2(src_path, dest)
        return dest

        machine = Machine(
            code=code, name=name, model=model,
            serial_number=serial_number,
            installation_date=installation_date, zone=zone
        )
        self.db.add(machine)
        self.commit()
        self.log_audit("CREATE", "machines", machine.id, f"เพิ่มเครื่องจักร {code}")
        self.commit()
        return machine

    def get_all_machines(self):
        return self.db.query(Machine).all()

    def generate_qr(self, machine_code):
        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(f"MACHINE:{machine_code}")
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")
        qr_dir = os.path.join("assets", "qrcodes")
        os.makedirs(qr_dir, exist_ok=True)
        filepath = os.path.join(qr_dir, f"{machine_code}.png")
        img.save(filepath)
        return filepath

    def add_attachment(self, machine_id, file_path, file_type):
        dest_dir = os.path.join("assets", "attachments", str(machine_id))
        os.makedirs(dest_dir, exist_ok=True)
        filename = os.path.basename(file_path)
        dest_path = os.path.join(dest_dir, filename)
        shutil.copy2(file_path, dest_path)
        attachment = MachineAttachment(
            machine_id=machine_id, file_path=dest_path, file_type=file_type
        )
        self.db.add(attachment)
        self.log_audit("ATTACH", "machine_attachments", attachment.id, f"แนบ {file_type}")
        self.commit()
        return attachment


class SettingsService:
    @staticmethod
    def get_setting(key: str, default=None):
        from models import SessionLocal, SystemSettings
        db = SessionLocal()
        try:
            setting = db.query(SystemSettings).filter(SystemSettings.key == key).first()
            if setting:
                return setting.value
            return default
        finally:
            db.close()

    @staticmethod
    def set_setting(key: str, value: str):
        from models import SessionLocal, SystemSettings
        db = SessionLocal()
        try:
            setting = db.query(SystemSettings).filter(SystemSettings.key == key).first()
            if setting:
                setting.value = value
            else:
                new_setting = SystemSettings(key=key, value=value)
                db.add(new_setting)
            db.commit()
        except Exception as e:
            db.rollback()
            raise e
        finally:
            db.close()
