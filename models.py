from sqlalchemy import create_engine, Column, Integer, String, Boolean, DateTime, Float, ForeignKey, Text
from sqlalchemy.orm import declarative_base, sessionmaker, relationship
from sqlalchemy.sql import func
from utils import config, logger
import datetime

db_url = config.get('Database', 'url', fallback='sqlite:///masapp_fallback.db')

try:
    if db_url.startswith('postgresql'):
        # PostgreSQL specific pool settings
        engine = create_engine(db_url, pool_size=20, max_overflow=30, pool_pre_ping=True)
    else:
        # SQLite pool settings
        engine = create_engine(db_url)
        
    with engine.connect() as conn:
        logger.info(f"Database connection initialized: {db_url.split('@')[-1] if '@' in db_url else db_url}")
except Exception as e:
    logger.error(f"Failed to initialize database engine: {e}")
    engine = None

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    password_hash = Column(String(128), nullable=False)
    role = Column(String(20), nullable=False, default='Viewer')
    full_name = Column(String(100))
    is_active = Column(Boolean, default=True)

class AuditLog(Base):
    __tablename__ = 'audit_logs'
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    action = Column(String(50), nullable=False)
    table_name = Column(String(50))
    record_id = Column(Integer)
    details = Column(Text)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    ip_address = Column(String(50))

# ─────────────────────────────────────────────────────────────
#  System Settings  –  ตั้งค่าระบบ
# ─────────────────────────────────────────────────────────────
class SystemSettings(Base):
    __tablename__ = 'system_settings'
    key   = Column(String(100), primary_key=True, index=True)
    value = Column(Text, nullable=True)

# ─────────────────────────────────────────────────────────────
#  Machine Intake Form  –  ใบรับเครื่องจักร (pre-approval)
# ─────────────────────────────────────────────────────────────
class MachineIntakeForm(Base):
    __tablename__ = 'machine_intake_forms'

    id              = Column(Integer, primary_key=True, index=True)
    form_number     = Column(String(30), unique=True, index=True)   # MR-2026-0001

    # ── ข้อมูลพื้นฐาน ──────────────────────────────────────────
    code            = Column(String(50), nullable=False)
    name            = Column(String(100), nullable=False)
    model           = Column(String(100))
    serial_number   = Column(String(100))
    zone            = Column(String(100))
    installation_date = Column(DateTime)

    # ── สเปคไฟฟ้า ───────────────────────────────────────────────
    power_kw        = Column(Float)          # กำลังไฟ kW
    voltage_v       = Column(Float)          # แรงดัน V
    current_amp     = Column(Float)          # กระแสไฟ A
    phase           = Column(Integer, default=3)   # 1 หรือ 3 เฟส
    dimensions      = Column(String(200))    # กxยxส (mm)
    weight_kg       = Column(Float)          # น้ำหนัก kg

    # ── ซัพพลายเออร์ ────────────────────────────────────────────
    supplier_name   = Column(String(100))
    supplier_contact= Column(String(100))    # เบอร์โทร
    supplier_sales  = Column(String(100))    # ชื่อเซลล์
    warranty_months = Column(Integer)        # ประกัน (เดือน)

    # ── ด้านความปลอดภัย ─────────────────────────────────────────
    safety_checked  = Column(Boolean, default=False)   # อุปกรณ์ความปลอดภัยครบ
    safety_notes    = Column(Text)

    # ── อะไหล่ ──────────────────────────────────────────────────
    spare_parts_checked = Column(Boolean, default=False)  # spare parts ครบ
    spare_parts_notes   = Column(Text)

    # ── คู่มือเครื่องจักร ───────────────────────────────────────
    has_manual      = Column(Boolean, default=False)
    manual_file_path= Column(String(500))   # path ไปยัง PDF

    # ── การอบรม ─────────────────────────────────────────────────
    training_done   = Column(Boolean, default=False)
    training_file_path = Column(String(500))  # เอกสารอบรม
    training_notes  = Column(Text)

    # ── ไฟล์เซ็นอนุมัติ (สแกนใบหน้างาน) ───────────────────────────
    signed_form_path = Column(String(500))

    # ── Workflow ─────────────────────────────────────────────────
    # Draft | Pending | Approved | Rejected
    status          = Column(String(20), default='Draft')
    submitted_by_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    approved_by_id  = Column(Integer, ForeignKey('users.id'), nullable=True)
    submitted_at    = Column(DateTime(timezone=True))
    approved_at     = Column(DateTime(timezone=True))
    reject_reason   = Column(Text)
    notes           = Column(Text)

    created_at      = Column(DateTime(timezone=True), server_default=func.now())

    submitted_by    = relationship("User", foreign_keys=[submitted_by_id])
    approved_by     = relationship("User", foreign_keys=[approved_by_id])
    machine         = relationship("Machine", back_populates="intake_form", uselist=False)

# ─────────────────────────────────────────────────────────────
#  Machine Registry  –  ทะเบียนเครื่องจักร (after approval)
# ─────────────────────────────────────────────────────────────
class Machine(Base):
    __tablename__ = 'machines'
    id              = Column(Integer, primary_key=True, index=True)
    code            = Column(String(50), unique=True, index=True, nullable=False)
    name            = Column(String(100), nullable=False)
    model           = Column(String(100))
    serial_number   = Column(String(100))
    installation_date = Column(DateTime)
    warranty_expiry = Column(DateTime)
    status          = Column(String(20), default='Running')  # Running, Warning, Breakdown
    zone            = Column(String(50))
    responsible_person = Column(String(100))  # ผู้รับผิดชอบ

    # ── Extended spec fields (populated from approved intake form) ──
    power_kw        = Column(Float)
    voltage_v       = Column(Float)
    current_amp     = Column(Float)
    phase           = Column(Integer, default=3)
    dimensions      = Column(String(200))
    weight_kg       = Column(Float)
    supplier_name   = Column(String(100))
    supplier_contact= Column(String(100))
    supplier_sales  = Column(String(100))
    warranty_months = Column(Integer)
    has_manual      = Column(Boolean, default=False)
    manual_file_path= Column(String(500))
    training_done   = Column(Boolean, default=False)

    # ── Operating Conditions (For Condition-Based PM) ──
    current_running_hours = Column(Float, default=0.0)
    current_cycle_count   = Column(Integer, default=0)

    # Link back to the original intake form
    intake_form_id  = Column(Integer, ForeignKey('machine_intake_forms.id'))

    map_id          = Column(Integer, ForeignKey('factory_maps.id'), nullable=True)
    map_x           = Column(Float, nullable=True)
    map_y           = Column(Float, nullable=True)

    intake_form = relationship("MachineIntakeForm", back_populates="machine")
    pm_plans    = relationship("PMPlan", back_populates="machine")
    work_orders = relationship("WorkOrder", back_populates="machine")
    factory_map = relationship("FactoryMap", back_populates="machines")
    attachments = relationship("MachineAttachment", back_populates="machine")

class FactoryMap(Base):
    __tablename__ = 'factory_maps'
    id          = Column(Integer, primary_key=True, index=True)
    name        = Column(String(150), nullable=False)
    image_path  = Column(String(255), nullable=False)
    created_at  = Column(DateTime(timezone=True), server_default=func.now())
    
    machines    = relationship("Machine", back_populates="factory_map")

class MachineAttachment(Base):
    __tablename__ = 'machine_attachments'
    id          = Column(Integer, primary_key=True, index=True)
    machine_id  = Column(Integer, ForeignKey('machines.id'), nullable=False)
    file_path   = Column(String(255), nullable=False)
    file_type   = Column(String(50))  # Manual, Warranty, Certificate, etc.
    upload_date = Column(DateTime(timezone=True), server_default=func.now())

    machine = relationship("Machine", back_populates="attachments")

class PMPlan(Base):
    __tablename__ = 'pm_plans'
    id              = Column(Integer, primary_key=True, index=True)
    machine_id      = Column(Integer, ForeignKey('machines.id'), nullable=False)
    title           = Column(String(150), nullable=False)
    standard        = Column(String(200)) # มาตรฐานการตรวจ
    description     = Column(Text)
    
    plan_type       = Column(String(20), default="PM") # "PM" or "AM"
    schedule_type   = Column(String(50), default="Calendar") # "Calendar" or "Condition"
    schedule_subtype= Column(String(50), default="Interval") # "Interval", "Weekly", "Monthly", etc.
    frequency_days  = Column(Integer, nullable=True) # Used if Interval
    schedule_day    = Column(Integer, nullable=True) # E.g., Day of week (0-6), or Day of month (-1 for end)
    trigger_value   = Column(Float, nullable=True)   # Next target running hours or cycle count
    
    last_done_date  = Column(DateTime)
    next_due_date   = Column(DateTime, nullable=True)
    is_calibration  = Column(Boolean, default=False)

    machine     = relationship("Machine", back_populates="pm_plans")
    checklists  = relationship("PMChecklistItem", back_populates="pm_plan", cascade="all, delete-orphan")
    work_orders = relationship("WorkOrder", back_populates="pm_plan")

class PMChecklistItem(Base):
    __tablename__ = 'pm_checklist_items'
    id          = Column(Integer, primary_key=True, index=True)
    pm_plan_id  = Column(Integer, ForeignKey('pm_plans.id'), nullable=False)
    task_name   = Column(String(200), nullable=False)
    task_type   = Column(String(20)) # e.g., 'C', 'I', 'L', 'T' or 'General'
    standard    = Column(String(200)) # มาตรฐานการตรวจ
    responsible_role = Column(String(100)) # ผู้รับผิดชอบ (พนักงาน, หัวหน้า)
    is_parameter = Column(Boolean, default=False)
    parameter_unit = Column(String(20))
    sequence    = Column(Integer, default=0)

    pm_plan     = relationship("PMPlan", back_populates="checklists")

class WorkOrder(Base):
    __tablename__ = 'work_orders'
    id              = Column(Integer, primary_key=True, index=True)
    machine_id      = Column(Integer, ForeignKey('machines.id'), nullable=False)
    pm_plan_id      = Column(Integer, ForeignKey('pm_plans.id'), nullable=True)
    
    wo_type         = Column(String(20), default='Repair')  # Repair, PM, AM
    reported_by_id  = Column(Integer, ForeignKey('users.id'), nullable=True)
    assigned_to_id  = Column(Integer, ForeignKey('users.id'), nullable=True)
    description     = Column(Text, nullable=False)
    status          = Column(String(20), default='Open')    # Open, Progress, Closed, WaitHandover
    priority        = Column(String(20), default='Normal')  # Normal, High, Critical
    
    actual_minutes  = Column(Integer, default=0)            # For Cost Tracking
    
    root_cause_why1 = Column(Text)
    root_cause_why2 = Column(Text)
    root_cause_why3 = Column(Text)
    root_cause_why4 = Column(Text)
    root_cause_why5 = Column(Text)
    action_taken    = Column(Text)
    created_at      = Column(DateTime(timezone=True), server_default=func.now())
    closed_at       = Column(DateTime(timezone=True))

    machine           = relationship("Machine", back_populates="work_orders")
    pm_plan           = relationship("PMPlan", back_populates="work_orders")
    parts_used        = relationship("WorkOrderPart", back_populates="work_order")
    permits           = relationship("WorkPermit", back_populates="work_order")
    attachments       = relationship("WorkOrderAttachment", back_populates="work_order", cascade="all, delete-orphan")
    checklist_results = relationship("WorkOrderChecklistResult", back_populates="work_order", cascade="all, delete-orphan")

class WorkOrderAttachment(Base):
    __tablename__ = 'work_order_attachments'
    id              = Column(Integer, primary_key=True, index=True)
    work_order_id   = Column(Integer, ForeignKey('work_orders.id'), nullable=False)
    file_path       = Column(String(255), nullable=False)
    file_type       = Column(String(50))  # e.g., 'PhotoEvidence'
    upload_date     = Column(DateTime(timezone=True), server_default=func.now())

    work_order      = relationship("WorkOrder", back_populates="attachments")

class WorkOrderChecklistResult(Base):
    __tablename__ = 'wo_checklist_results'
    id              = Column(Integer, primary_key=True, index=True)
    work_order_id   = Column(Integer, ForeignKey('work_orders.id'), nullable=False)
    checklist_item_id = Column(Integer, ForeignKey('pm_checklist_items.id'), nullable=True)
    task_name       = Column(String(200))
    standard        = Column(String(200))
    responsible_role = Column(String(100))
    is_checked      = Column(Boolean, default=False)
    parameter_value = Column(String(50))
    defect_noted    = Column(Boolean, default=False)
    defect_details  = Column(Text)

    work_order      = relationship("WorkOrder", back_populates="checklist_results")
    checklist_item  = relationship("PMChecklistItem")

class WorkPermit(Base):
    __tablename__ = 'work_permits'
    id              = Column(Integer, primary_key=True, index=True)
    work_order_id   = Column(Integer, ForeignKey('work_orders.id'), nullable=False)
    permit_type     = Column(String(50), nullable=False)
    status          = Column(String(20), default='Pending')
    requested_by_id = Column(Integer, ForeignKey('users.id'))
    approved_by_id  = Column(Integer, ForeignKey('users.id'))
    created_at      = Column(DateTime(timezone=True), server_default=func.now())

    work_order = relationship("WorkOrder", back_populates="permits")

class Supplier(Base):
    __tablename__ = 'suppliers'
    id              = Column(Integer, primary_key=True, index=True)
    name            = Column(String(100), nullable=False)
    contact_info    = Column(String(255))
    lead_time_days  = Column(Integer)

class SparePart(Base):
    __tablename__ = 'spare_parts'
    id              = Column(Integer, primary_key=True, index=True)
    code            = Column(String(50), unique=True, index=True, nullable=False)
    name            = Column(String(100), nullable=False)
    description     = Column(Text)
    min_stock       = Column(Integer, default=5)
    current_stock   = Column(Integer, default=0)
    unit_price      = Column(Float, default=0.0)
    location        = Column(String(100))
    supplier_id     = Column(Integer, ForeignKey('suppliers.id'))

class WorkOrderPart(Base):
    __tablename__ = 'work_order_parts'
    id              = Column(Integer, primary_key=True, index=True)
    work_order_id   = Column(Integer, ForeignKey('work_orders.id'), nullable=False)
    part_id         = Column(Integer, ForeignKey('spare_parts.id'), nullable=False)
    quantity_used   = Column(Integer, nullable=False)

    work_order = relationship("WorkOrder", back_populates="parts_used")

# Create tables automatically if they don't exist
if engine:
    Base.metadata.create_all(bind=engine)
