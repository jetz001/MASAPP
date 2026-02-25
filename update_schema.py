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
        
        # Add columns to pm_checklist_items
        print("Updating pm_checklist_items...")
        try:
            cur.execute("ALTER TABLE pm_checklist_items ADD COLUMN standard VARCHAR(200);")
            print("  Added 'standard' to pm_checklist_items")
        except Exception as e:
            print(f"  Note: 'standard' might already exist or error: {e}")
            
        try:
            cur.execute("ALTER TABLE pm_checklist_items ADD COLUMN responsible_role VARCHAR(100);")
            print("  Added 'responsible_role' to pm_checklist_items")
        except Exception as e:
            print(f"  Note: 'responsible_role' might already exist or error: {e}")
            
        # Add columns to wo_checklist_results
        print("Updating wo_checklist_results...")
        try:
            cur.execute("ALTER TABLE wo_checklist_results ADD COLUMN standard VARCHAR(200);")
            print("  Added 'standard' to wo_checklist_results")
        except Exception as e:
            print(f"  Note: 'standard' might already exist or error: {e}")
            
        try:
            cur.execute("ALTER TABLE wo_checklist_results ADD COLUMN responsible_role VARCHAR(100);")
            print("  Added 'responsible_role' to wo_checklist_results")
        except Exception as e:
            print(f"  Note: 'responsible_role' might already exist or error: {e}")
            
        cur.close()
        conn.close()
        print("\nMigration completed successfully!")
        
    except Exception as e:
        print(f"Migration failed: {e}")

if __name__ == "__main__":
    run_migration()
