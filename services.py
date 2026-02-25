from models import SessionLocal, User, AuditLog, WorkOrder, WorkOrderChecklistResult, WorkOrderAttachment, PMPlan, PMChecklistItem
import hashlib
import shutil, os
from datetime import datetime
from utils import config, logger

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
        logger.info(f"UserService: [REQ] Creating user '{username}' (Role: {role})")
        if requester_role not in [ROLE_ADMIN]:
            logger.warning(f"UserService: [403 Forbidden] Non-admin requester tried to create user '{username}'")
            raise PermissionError("เฉพาะ Admin เท่านั้นที่สามารถสร้างผู้ใช้งานได้")
        user = User(
            username=username,
            password_hash=self.hash_password(password),
            role=role,
            full_name=full_name
        )
        self.db.add(user)
        self.commit()
        logger.info(f"UserService: [200 OK] User '{username}' created successfully ID={user.id}")
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
        logger.info(f"UserService: [REQ] Resetting password for user ID={user_id}")
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            logger.warning(f"UserService: [404 Not Found] Reset password failed - User ID {user_id} not found")
            raise ValueError("ไม่พบผู้ใช้งาน")
        user.password_hash = self.hash_password(new_password)
        self.log_audit("RESET_PW", "users", user.id, "รีเซ็ตรหัสผ่าน")
        self.commit()
        logger.info(f"UserService: [200 OK] Password reset successfully ID={user_id}")

    def delete_user(self, user_id: int):
        logger.info(f"UserService: [REQ] Deleting user ID={user_id}")
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            logger.warning(f"UserService: [404 Not Found] Deletion failed - User ID {user_id} not found")
            raise ValueError("ไม่พบผู้ใช้งาน")
        username = user.username
        self.db.delete(user)
        self.log_audit("DELETE", "users", user_id, f"ลบผู้ใช้ {username}")
        self.commit()
        logger.info(f"UserService: [200 OK] User '{username}' deleted successfully")

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
        logger.info(f"FactoryMapService: [REQ] Creating new factory map '{name}'")
        from models import FactoryMap
        new_map = FactoryMap(
            name=name,
            image_path=image_path
        )
        self.db.add(new_map)
        self.db.commit()
        self.db.refresh(new_map)
        logger.info(f"FactoryMapService: [200 OK] Map '{name}' created successfully ID={new_map.id}")
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
        logger.info(f"MachineService: [REQ] Adding machine '{code}'")
        machine = Machine(
            code=code, name=name, model=model,
            serial_number=serial_number,
            installation_date=installation_date, zone=zone,
            **kwargs
        )
        self.db.add(machine)
        self.commit()
        logger.info(f"MachineService: [200 OK] Machine '{code}' added successfully ID={machine.id}")
        self.log_audit("CREATE", "machines", machine.id, f"เพิ่มเครื่องจักร {code}")
        self.commit()
        return machine

    def get_all_machines(self):
        return self.db.query(Machine).all()

    def get_machine(self, machine_id: int):
        return self.db.query(Machine).filter(Machine.id == machine_id).first()

    def update_machine(self, machine_id: int, **kwargs):
        logger.info(f"MachineService: [REQ] Updating machine ID={machine_id}")
        m = self.db.query(Machine).filter(Machine.id == machine_id).first()
        if not m:
            logger.warning(f"MachineService: [404 Not Found] Update failed - Machine ID {machine_id} not found")
            raise ValueError("ไม่พบเครื่องจักร")
        for k, v in kwargs.items():
            if hasattr(m, k):
                setattr(m, k, v)
        self.log_audit("UPDATE", "machines", machine_id, str(kwargs))
        self.commit()
        logger.info(f"MachineService: [200 OK] Machine updated successfully ID={machine_id}")
        return m

    def delete_machine(self, machine_id: int):
        logger.info(f"MachineService: [REQ] Deleting machine ID={machine_id}")
        m = self.db.query(Machine).filter(Machine.id == machine_id).first()
        if not m:
            logger.warning(f"MachineService: [404 Not Found] Deletion failed - Machine ID {machine_id} not found")
            raise ValueError("ไม่พบเครื่องจักร")
        code = m.code
        self.db.delete(m)
        self.log_audit("DELETE", "machines", machine_id, f"ลบเครื่องจักร {code}")
        self.commit()
        logger.info(f"MachineService: [200 OK] Machine '{code}' deleted successfully")

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
        logger.info(f"IntakeFormService: Creating new form for '{data.get('machine_name')}'")
        form = MachineIntakeForm(
            form_number    = self._next_form_number(),
            submitted_by_id= submitted_by_id,
            status         = self.DRAFT,
            **{k: v for k, v in data.items() if hasattr(MachineIntakeForm, k)}
        )
        self.db.add(form)
        self.commit()
        logger.info(f"IntakeFormService: [200 OK] Form '{form.form_number}' created ID={form.id}")
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
        logger.info(f"IntakeFormService: [REQ] Submitting form ID={form_id} for approval")
        if requester_role == ROLE_VIEWER:
            logger.warning(f"IntakeFormService: [403 Forbidden] Viewer tried to submit form ID={form_id}")
            raise PermissionError("Viewer ไม่สามารถส่งขออนุมัติได้")
        form = self._get_or_raise(form_id)
        if form.status not in (self.DRAFT, self.REJECTED):
            logger.warning(f"IntakeFormService: [400 Bad Request] Submit failed - Form ID {form_id} status is {form.status}")
            raise ValueError(f"ไม่สามารถส่งได้ — สถานะปัจจุบัน: {form.status}")
        import datetime as dt
        form.status      = self.PENDING
        form.submitted_at= dt.datetime.now()
        self.log_audit("SUBMIT", "machine_intake_forms", form_id,
                       f"ส่งขออนุมัติ {form.form_number}")
        self.commit()
        logger.info(f"IntakeFormService: [200 OK] Form '{form.form_number}' submitted successfully")
        return form

    def approve_form(self, form_id: int, approver_id: int,
                     approver_role: str) -> Machine:
        """Pending → Approved + creates Machine in registry."""
        logger.info(f"IntakeFormService: [REQ] Approving form ID={form_id}")
        if approver_role not in self.APPROVER_ROLES:
            logger.warning(f"IntakeFormService: [403 Forbidden] Approver role {approver_role} is insufficient for form ID={form_id}")
            raise PermissionError("เฉพาะ Manager หรือ Admin เท่านั้นที่อนุมัติได้")
        form = self._get_or_raise(form_id)
        if form.status != self.PENDING:
            logger.warning(f"IntakeFormService: [400 Bad Request] Approval failed - Form ID {form_id} status is {form.status}")
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
        logger.info(f"IntakeFormService: [200 OK] Form ID={form_id} approved. Created machine ID={machine.id}")
        return machine

    def reject_form(self, form_id: int, approver_id: int,
                    approver_role: str, reason: str = ""):
        """Pending → Rejected."""
        logger.info(f"IntakeFormService: [REQ] Rejecting form ID={form_id}")
        if approver_role not in self.APPROVER_ROLES:
            logger.warning(f"IntakeFormService: [403 Forbidden] Rejecter role {approver_role} is insufficient for form ID={form_id}")
            raise PermissionError("เฉพาะ Manager หรือ Admin เท่านั้นที่ปฏิเสธได้")
        form = self._get_or_raise(form_id)
        if form.status != self.PENDING:
            logger.warning(f"IntakeFormService: [400 Bad Request] Rejection failed - Form ID {form_id} status is {form.status}")
            raise ValueError(f"ต้องเป็นสถานะ Pending — ปัจจุบัน: {form.status}")
        form.status      = self.REJECTED
        form.reject_reason = reason
        self.log_audit("REJECT", "machine_intake_forms", form_id,
                       f"ปฏิเสธ {form.form_number}: {reason}")
        self.commit()
        logger.info(f"IntakeFormService: [200 OK] Form ID={form_id} rejected successfully")
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
        finally:
            db.close()

# ─────────────────────────────────────────────────────────────
#  PM Plan & AM Service (Module 4)
# ─────────────────────────────────────────────────────────────
from models import PMPlan, PMChecklistItem, WorkOrder, WorkOrderAttachment, WorkOrderChecklistResult

class PMService(BaseService):
    def get_all_plans(self, plan_type=None):
        query = self.db.query(PMPlan)
        if plan_type:
            query = query.filter(PMPlan.plan_type == plan_type)
        return query.all()

    def get_plans_for_machine(self, machine_id: int):
        return self.db.query(PMPlan).filter(PMPlan.machine_id == machine_id).all()

    def create_plan(self, data: dict, checklists: list = None):
        self.require("pm_plan", "create")
        logger.info(f"PMService: [REQ] Creating new plan '{data.get('detail') or data.get('title')}'")
        
        # Map simplified fields from the new AddPMPlanDialog
        if 'detail' in data:
            data['title'] = data.pop('detail')
        if 'notes' in data:
            data['description'] = data.pop('notes')
            
        plan = PMPlan(**{k: v for k, v in data.items() if hasattr(PMPlan, k)})
        self.db.add(plan)
        self.db.flush() # Get ID
        
        # Auto-generate first checklist item if 'standard' provided
        if 'standard' in data:
            item = PMChecklistItem(
                pm_plan_id=plan.id,
                task_name=plan.title,
                standard=data.get('standard', ''),
                task_type='General',
                sequence=1
            )
            self.db.add(item)
            logger.debug(f"PMService: Auto-generated first checklist item for plan ID {plan.id}")

        if checklists:
            for idx, cl in enumerate(checklists):
                item = PMChecklistItem(
                    pm_plan_id=plan.id,
                    task_name=cl.get('task_name'),
                    task_type=cl.get('task_type', 'General'),
                    standard=cl.get('standard', ''),
                    responsible_role=cl.get('responsible_role', ''),
                    is_parameter=cl.get('is_parameter', False),
                    parameter_unit=cl.get('parameter_unit', ''),
                    sequence=idx + (2 if 'standard' in data else 1)
                )
                self.db.add(item)
        
        self.commit()
        logger.info(f"PMService: [200 OK] Plan created successfully ID={plan.id}, Title='{plan.title}'")
        self.log_audit("CREATE", "pm_plans", plan.id, f"สร้างแผน {plan.plan_type}: {plan.title}")
        return plan

    def update_plan(self, plan_id: int, data: dict, checklists: list = None):
        self.require("pm_plan", "update")
        logger.info(f"PMService: [REQ] Updating plan ID={plan_id}")
        plan = self.db.query(PMPlan).filter(PMPlan.id == plan_id).first()
        if not plan: 
            logger.warning(f"PMService: [404 Not Found] Update failed - Plan ID {plan_id} not found")
            raise ValueError("ไม่พบแผนบำรุงรักษา")
        
        # Map simplified fields from the dialog
        if 'detail' in data:
            data['title'] = data.pop('detail')
        if 'notes' in data:
            data['description'] = data.pop('notes')

        for k, v in data.items():
            if hasattr(plan, k):
                setattr(plan, k, v)
                
        if checklists is not None:
            logger.debug(f"PMService: Updating checklists for plan ID {plan_id}")
            # Delete old checklists
            self.db.query(PMChecklistItem).filter(PMChecklistItem.pm_plan_id == plan_id).delete()
            # Add new checklists
            for idx, cl in enumerate(checklists):
                item = PMChecklistItem(
                    pm_plan_id=plan.id,
                    task_name=cl.get('task_name'),
                    task_type=cl.get('task_type', 'General'),
                    standard=cl.get('standard', ''),
                    responsible_role=cl.get('responsible_role', ''),
                    is_parameter=cl.get('is_parameter', False),
                    parameter_unit=cl.get('parameter_unit', ''),
                    sequence=idx
                )
                self.db.add(item)
                
        self.log_audit("UPDATE", "pm_plans", plan.id, f"อัปเดตแผน: {plan.title}")
        self.commit()
        logger.info(f"PMService: [200 OK] Plan updated successfully ID={plan.id}")
        return plan

    def delete_plan(self, plan_id: int):
        self.require("pm_plan", "delete")
        logger.info(f"PMService: [REQ] Requesting deletion of plan ID={plan_id}")
        plan = self.db.query(PMPlan).filter(PMPlan.id == plan_id).first()
        if not plan: 
            logger.warning(f"PMService: [404 Not Found] Deletion failed - Plan ID {plan_id} not found")
            raise ValueError("ไม่พบแผนบำรุงรักษา")
        
        # ── Fix: IntegrityError prevention ────────────────────
        # Before deleting the plan and its items, we must nullify references in WorkOrder data
        # so we don't violate FK constraints in wo_checklist_results
        
        item_ids = [it.id for it in plan.checklists]
        if item_ids:
            # Nullify references in results
            self.db.query(WorkOrderChecklistResult).filter(
                WorkOrderChecklistResult.checklist_item_id.in_(item_ids)
            ).update({"checklist_item_id": None}, synchronize_session=False)
            logger.debug(f"PMService: Nullified {len(item_ids)} checklist item references in WO results")

        # Nullify references in WorkOrders themselves
        self.db.query(WorkOrder).filter(
            WorkOrder.pm_plan_id == plan_id
        ).update({"pm_plan_id": None}, synchronize_session=False)
        logger.debug(f"PMService: Nullified plan references in WorkOrders for plan ID {plan_id}")
        # ────────────────────────────────────────────────────────

        title = plan.title
        self.db.delete(plan)
        self.log_audit("DELETE", "pm_plans", plan_id, f"ลบแผน: {title}")
        self.commit()
        logger.info(f"PMService: [200 OK] Plan deleted successfully ID={plan_id}")

    def generate_tasks_for_due_plans(self):
        """CRON-like job: Automatically checks all plans and generates WorkOrders for due ones."""
        import datetime as dt
        now = dt.datetime.now()
        logger.info(f"PMService: [REQ] Running automated task generation (Now: {now})")
        
        # Check Calendar-based plans
        due_plans = self.db.query(PMPlan).filter(
            PMPlan.schedule_type == "Calendar",
            PMPlan.next_due_date != None,
            PMPlan.next_due_date <= now
        ).all()
        
        if due_plans:
            logger.info(f"PMService: Found {len(due_plans)} due calendar plans")
        
        generated = []
        for p in due_plans:
            if p.plan_type == "AM":
                # Skip automated WO generation for AM (per user request: operators have no computers)
                # But we still update the next due date so the plan doesn't stay 'due'
                if p.frequency_days:
                    p.last_done_date = now
                    p.next_due_date = now + dt.timedelta(days=p.frequency_days)
                continue

            # Avoid creating duplicates if there's already an active open PM/AM for this plan
            existing = self.db.query(WorkOrder).filter(
                WorkOrder.pm_plan_id == p.id,
                WorkOrder.status.in_(["Open", "Progress", "WaitHandover"])
            ).first()
            if existing: 
                logger.debug(f"PMService: Skipping plan ID {p.id}, active WO already exists")
                continue
            
            logger.info(f"PMService: Generating automated task for plan ID {p.id} ({p.title})")
            # Create a WorkOrder wrapper for this PM/AM
            wo = WorkOrder(
                machine_id=p.machine_id,
                pm_plan_id=p.id,
                wo_type=p.plan_type,
                description=f"Automated Task: {p.title}",
                priority="Normal",
                status="Open"
            )
            self.db.add(wo)
            self.db.flush()
            
            # Copy checklist items into the WorkOrder
            for cl in p.checklists:
                res = WorkOrderChecklistResult(
                    work_order_id=wo.id,
                    checklist_item_id=cl.id,
                    task_name=cl.task_name,
                    is_checked=False
                )
                self.db.add(res)
                
            # Calculate next due date simply by interval currently
            if p.frequency_days:
                p.last_done_date = now
                p.next_due_date = now + dt.timedelta(days=p.frequency_days)
            
            self.log_audit("SYSTEM", "work_orders", wo.id, f"ระบบสร้างใบแจ้งงานอัตโนมัติ: {wo.wo_type} จากแผน {p.title}")
            generated.append(wo)
        
        if generated:
            self.commit()
            logger.info(f"PMService: [200 OK] Successfully generated {len(generated)} automated tasks")
        return generated

    def update_plan_after_task(self, plan_id: int):
        import datetime as dt
        plan = self.db.query(PMPlan).get(plan_id)
        if not plan: return
        
        now = dt.datetime.now()
        plan.last_done_date = now
        
        # Calculate next due
        if plan.schedule_type == "Calendar":
            if plan.frequency_days:
                plan.next_due_date = now + dt.timedelta(days=plan.frequency_days)
        elif plan.schedule_type == "Condition":
            # For condition based, we increment the target trigger
            # We use frequency_days field as the 'interval' for condition if set
            interval = plan.frequency_days if plan.frequency_days else plan.trigger_value
            if interval:
                plan.trigger_value += interval
                
        self.log_audit("UPDATE", "pm_plans", plan_id, f"อัปเดตกำหนดการบำรุงรักษาถัดไปหลังปิดงาน")
        self.commit()

# ─────────────────────────────────────────────────────────────
#  Work Order Service (Module 5 + Module 4 Tasks)
# ─────────────────────────────────────────────────────────────
class WorkOrderService(BaseService):
    def get_all_work_orders(self, wo_type=None):
        query = self.db.query(WorkOrder)
        if wo_type:
            query = query.filter(WorkOrder.wo_type == wo_type)
        return query.order_by(WorkOrder.created_at.desc()).all()

    def create_work_order(self, data: dict, checklists: list = None):
        logger.info(f"WorkOrderService: [REQ] Creating new work order of type '{data.get('wo_type')}'")
        user_id = self.current_user_id
        if "reported_by_id" not in data and user_id:
            data["reported_by_id"] = user_id
            
        wo = WorkOrder(**{k: v for k, v in data.items() if hasattr(WorkOrder, k)})
        self.db.add(wo)
        self.db.flush()
        
        if checklists:
            logger.debug(f"WorkOrderService: Adding {len(checklists)} checklist items to WO ID {wo.id}")
            for cl in checklists:
                res = WorkOrderChecklistResult(
                    work_order_id=wo.id,
                    checklist_item_id=cl.get('id'),
                    task_name=cl.get('task_name'),
                    is_checked=False
                )
                self.db.add(res)
                
        self.log_audit("CREATE", "work_orders", wo.id, f"สร้างใบแจ้งงาน {wo.wo_type}")
        self.commit()
        logger.info(f"WorkOrderService: [200 OK] Work order created successfully ID={wo.id}")
        return wo

    def update_work_order(self, wo_id: int, data: dict, checklist_results: dict = None):
        logger.info(f"WorkOrderService: [REQ] Updating work order ID={wo_id}")
        wo = self.db.query(WorkOrder).filter(WorkOrder.id == wo_id).first()
        if not wo: 
            logger.warning(f"WorkOrderService: [404 Not Found] Update failed - WO ID {wo_id} not found")
            raise ValueError("ไม่พบใบแจ้งงาน")
        
        for k, v in data.items():
            if hasattr(wo, k):
                setattr(wo, k, v)
                
        if checklist_results:
            logger.debug(f"WorkOrderService: Updating {len(checklist_results)} checklist results for WO ID {wo_id}")
            for res_id, res_data in checklist_results.items():
                r = self.db.query(WorkOrderChecklistResult).filter(WorkOrderChecklistResult.id == int(res_id)).first()
                if r:
                    r.is_checked = res_data.get('is_checked', r.is_checked)
                    r.parameter_value = res_data.get('parameter_value', r.parameter_value)
                    r.defect_noted = res_data.get('defect_noted', r.defect_noted)
                    r.defect_details = res_data.get('defect_details', r.defect_details)
                    
        self.log_audit("UPDATE", "work_orders", wo.id, f"อัปเดตใบแจ้งงาน")
        self.commit()
        logger.info(f"WorkOrderService: [200 OK] Work order updated successfully ID={wo_id}")
        return wo
        
    def delete_work_order(self, wo_id: int):
        self.require("work_order", "delete")
        wo = self.db.query(WorkOrder).filter(WorkOrder.id == wo_id).first()
        if not wo: raise ValueError("ไม่พบใบแจ้งงาน")
        self.db.delete(wo)
        self.log_audit("DELETE", "work_orders", wo_id, f"ลบใบแจ้งงาน")
        self.commit()

    def add_attachment(self, wo_id: int, file_path: str, file_type: str = "PhotoEvidence"):
        """Save an attachment record for a work order."""
        wo = self.db.query(WorkOrder).get(wo_id)
        if not wo: raise ValueError("ไม่พบใบแจ้งงาน")
        
        # Ensure uploads dir exists
        upload_dir = os.path.join("uploads", "attachments", "work_orders")
        os.makedirs(upload_dir, exist_ok=True)
        
        filename = f"wo_{wo_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{os.path.basename(file_path)}"
        dest_path = os.path.join(upload_dir, filename)
        shutil.copy(file_path, dest_path)
        
        att = WorkOrderAttachment(
            work_order_id=wo_id,
            file_path=dest_path,
            file_type=file_type
        )
        self.db.add(att)
        self.commit()
        return att

    def get_attachments(self, wo_id: int):
        return self.db.query(WorkOrderAttachment).filter(WorkOrderAttachment.work_order_id == wo_id).all()

# ─────────────────────────────────────────────────────────────
#  Reporting Service (Module 4/5)
# ─────────────────────────────────────────────────────────────
class ReportingService(BaseService):
    def generate_am_checksheet(self, plan_id: int):
        from reportlab.lib.pagesizes import A4, landscape
        from reportlab.pdfgen import canvas
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
        import datetime as dt

        plan = self.db.query(PMPlan).get(plan_id)
        if not plan: raise ValueError("ไม่พบแผนที่ระบุ")

        # Font Registration (Prioritize Thai support)
        font_paths = [
            "C:\\Windows\\Fonts\\leelawad.ttf", # Leelawadee (Standard Thai)
            "C:\\Windows\\Fonts\\tahoma.ttf",   # Tahoma (Standard Thai)
            "assets/fonts/Padauk-Regular.ttf", # Padauk (Mainly Burmese)
            "C:\\Windows\\Fonts\\arial.ttf"
        ]
        thai_font_name = "ThaiFont"
        font_registered = False
        for fp in font_paths:
            if os.path.exists(fp):
                try:
                    pdfmetrics.registerFont(TTFont(thai_font_name, fp))
                    font_registered = True
                    logger.info(f"ReportingService: Registered '{thai_font_name}' from {fp}")
                    break
                except Exception as e:
                    logger.warning(f"ReportingService: Failed to register font {fp}: {e}")
                    continue
        
        if not font_registered:
            logger.error("ReportingService: No suitable Thai font found! Falling back to Helvetica (may show squares).")
            thai_font_name = "Helvetica"

        filename = f"monthly_checksheet_{plan.machine.code if plan.machine else 'NA'}_{plan_id}.pdf"
        output_dir = "exports/checksheets"
        os.makedirs(output_dir, exist_ok=True)
        pdf_path = os.path.abspath(os.path.join(output_dir, filename))
        
        c = canvas.Canvas(pdf_path, pagesize=landscape(A4))
        w, h = landscape(A4)
        
        # Draw Header Grid
        c.setLineWidth(0.5)
        # Draw Header Grid
        c.setLineWidth(0.5)
        # Main Header row
        c.rect(30, h - 80, w - 60, 50)
        
        # Logo Box
        logo_path = "assets/masapp_logo.png"
        if os.path.exists(logo_path):
            c.drawImage(logo_path, 35, h - 75, width=100, height=40, preserveAspectRatio=True)
        else:
            c.setFont(thai_font_name, 14)
            c.drawString(40, h - 60, "LOGO")

        # Header Title
        c.setFont(thai_font_name, 12)
        c.drawCentredString(w/2, h - 50, "เอกสารตรวจเช็คบำรุงรักษาเครื่องจักร")
        c.setFont(thai_font_name, 8)
        c.drawCentredString(w/2, h - 70, "( AM Monthly Checklist )")

        # Machine Info Row
        c.rect(30, h - 110, w - 60, 30)
        c.setFont(thai_font_name, 9)
        c.drawString(40, h - 95, f"M/C NO: {plan.machine.code if plan.machine else '-'}")
        c.drawString(160, h - 95, f"ชื่อเครื่องจักร: {plan.machine.name if plan.machine else '-'}")
        c.drawString(400, h - 95, f"รุ่น: {plan.machine.model if plan.machine else '-'}")
        c.drawString(650, h - 95, f"โซน: {plan.machine.zone if plan.machine else '-'}")

        # Table Column Headers
        col_task_w = 180
        col_std_w  = 120
        col_meta_w = col_task_w + col_std_w
        day_w = (w - 60 - col_meta_w) / 31
        
        y_header = h - 145
        c.rect(30, y_header, w - 60, 35) # Header row
        c.line(30 + col_task_w, y_header, 30 + col_task_w, y_header + 35)
        c.line(30 + col_meta_w, y_header, 30 + col_meta_w, y_header + 35)
        
        c.setFont(thai_font_name, 9)
        c.drawCentredString(30 + col_task_w/2, y_header + 12, "รายการตรวจสอบ (Task)")
        c.drawCentredString(30 + col_task_w + col_std_w/2, y_header + 12, "มาตรฐาน (Standard)")
        
        # Unified "วันที่" Header
        c.setFont(thai_font_name, 8)
        c.drawCentredString(30 + col_meta_w + (w-60-col_meta_w)/2, y_header + 22, "วันที่ (Date)")
        c.line(30 + col_meta_w, y_header + 18, w - 30, y_header + 18)

        # Day Numbers
        for day in range(1, 32):
            dx = 30 + col_meta_w + (day-1)*day_w
            if day > 1:
                c.line(dx, y_header, dx, y_header + 18)
            c.setFont(thai_font_name, 7)
            c.drawCentredString(dx + day_w/2, y_header + 5, str(day))

        # Data Rows
        y = y_header - 25
        items = plan.checklists
        
        if not items and plan.standard:
            items = [type('obj', (object,), {'task_name': plan.title, 'standard': plan.standard})]

        for item in items:
            row_h = 25 # Tighter row height
            if y < 50:
                c.showPage()
                y = h - 50
            
            c.rect(30, y, w - 60, row_h)
            c.line(30 + col_task_w, y, 30 + col_task_w, y + row_h)
            c.line(30 + col_meta_w, y, 30 + col_meta_w, y + row_h)
            
            c.setFont(thai_font_name, 8)
            tname = getattr(item, 'task_name', '-')
            sname = getattr(item, 'standard', '-')
            
            # Task name column
            c.drawString(35, y + 8, tname[:45] if len(tname) > 45 else tname)
            # Standard column
            c.drawString(35 + col_task_w, y + 8, sname[:30] if len(sname) > 30 else sname)
            
            # Grid for days
            for day in range(1, 32):
                dx = 30 + col_meta_w + (day-1)*day_w
                c.line(dx, y, dx, y + row_h)
                
            y -= row_h

        c.save()
        return pdf_path

    def generate_pm_work_order(self, wo_id: int):
        from reportlab.lib.pagesizes import A4
        from reportlab.pdfgen import canvas
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
        import datetime as dt

        wo = self.db.query(WorkOrder).get(wo_id)
        if not wo: raise ValueError("ไม่พบใบสั่งงานที่ระบุ")

        # Try to register Thai/Burmese font
        font_paths = [
            "assets/fonts/Padauk-Regular.ttf",
            "C:\\Windows\\Fonts\\leelawad.ttf", 
            "C:\\Windows\\Fonts\\tahoma.ttf"
        ]
        thai_font_name = "ThaiFont"
        font_registered = False
        for fp in font_paths:
            if os.path.exists(fp):
                try:
                    pdfmetrics.registerFont(TTFont(thai_font_name, fp))
                    font_registered = True
                    break
                except: continue
        
        if not font_registered: thai_font_name = "Helvetica"

        filename = f"workorder_{wo.wo_type}_{wo_id}.pdf"
        output_dir = "exports/workorders"
        os.makedirs(output_dir, exist_ok=True)
        pdf_path = os.path.abspath(os.path.join(output_dir, filename))
        
        c = canvas.Canvas(pdf_path, pagesize=A4)
        width, height = A4
        
        # Header
        c.setFont(thai_font_name, 18)
        c.drawString(50, height - 50, f"ใบสั่งงานบำรุงรักษา (Maintenance Work Order)")
        
        c.setFont(thai_font_name, 12)
        c.drawString(50, height - 80, f"เลขที่งาน: #{wo.id}")
        c.drawString(200, height - 80, f"ประเภท: {wo.wo_type}")
        c.drawString(400, height - 80, f"ลำดับความสำคัญ: {wo.priority or 'Normal'}")
        
        c.line(50, height - 90, 550, height - 90)
        c.drawString(50, height - 105, f"เครื่องจักร: {wo.machine.code if wo.machine else '-'} - {wo.machine.name if wo.machine else '-'}")
        c.drawString(50, height - 120, f"รายละเอียด: {wo.description}")
        c.line(50, height - 130, 550, height - 130)

        # Checklist Section
        c.setFont(thai_font_name, 14)
        c.drawString(50, height - 150, "รายการตรวจสอบ (Checklist):")
        y = height - 170
        for i, res in enumerate(wo.checklist_results):
            c.setFont(thai_font_name, 11)
            c.drawString(60, y, f"{i+1}. {res.task_name}")
            c.rect(480, y - 5, 12, 12)
            c.drawString(500, y, "Confirmed")
            y -= 25
            if y < 100:
                c.showPage()
                y = height - 50

        # Footer Signatures
        c.line(50, 100, 550, 100)
        c.setFont(thai_font_name, 10)
        c.drawString(50, 80, f"ผู้แจ้งงาน: ..............................")
        c.drawString(350, 80, f"ผู้อนุมัติ: ..............................")
        c.drawString(50, 40, f"ผู้ปฏิบัติงาน: ..............................")
        c.drawString(350, 40, f"วันที่แล้วเสร็จ: ....../....../......")
        
        c.save()
        return pdf_path
