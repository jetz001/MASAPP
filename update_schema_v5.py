import psycopg2
from configparser import ConfigParser
import os

def run_migration():
    # Read config
    config = ConfigParser()
    config.read('config.ini')
    db_url = config.get('Database', 'url')
    
    print(f"Connecting to {db_url}...")
    
    try:
        conn = psycopg2.connect(db_url)
        conn.autocommit = True
        cur = conn.cursor()
        
        # 1. Update machines table
        print("Updating machines...")
        execute_ignore(cur, "ALTER TABLE machines ADD COLUMN hourly_productive_rate REAL DEFAULT 0.0;")
        
        # 2. Update work_orders table
        print("Updating work_orders...")
        execute_ignore(cur, "ALTER TABLE work_orders ALTER COLUMN machine_id DROP NOT NULL;")
        execute_ignore(cur, "ALTER TABLE work_orders ALTER COLUMN wo_type TYPE VARCHAR(50);")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN origin VARCHAR(50) DEFAULT 'Manual';")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN is_approved BOOLEAN DEFAULT FALSE;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN sla_deadline TIMESTAMP WITH TIME ZONE;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN sla_elevated BOOLEAN DEFAULT FALSE;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN hold_reason TEXT;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN failure_code VARCHAR(50);")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN machine_downtime_minutes INTEGER DEFAULT 0;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN vendor_cost REAL DEFAULT 0.0;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN total_cost REAL DEFAULT 0.0;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN opportunity_cost REAL DEFAULT 0.0;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN requester_satisfaction_score INTEGER;")
        execute_ignore(cur, "ALTER TABLE work_orders ADD COLUMN requester_acceptance_note TEXT;")

        # Enable creation of new tables (work_order_labors, work_order_vendors)
        # We will just let models.py Base.metadata.create_all handle new tables.
        
        cur.close()
        conn.close()
        print("\nMigration completed successfully!")
        
    except Exception as e:
        print(f"Migration failed: {e}")

def execute_ignore(cur, sql):
    try:
        cur.execute(sql)
        print(f"  Success: {sql}")
    except Exception as e:
        print(f"  Ignored/Error for {sql}: {e}")

if __name__ == "__main__":
    run_migration()
