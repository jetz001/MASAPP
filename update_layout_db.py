import sqlite3
import sys

def main():
    try:
        db = sqlite3.connect('masapp.db')
        c = db.cursor()

        # 1. Create factory_maps table
        c.execute('''
            CREATE TABLE IF NOT EXISTS factory_maps (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name VARCHAR(150) NOT NULL,
                image_path VARCHAR(255) NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        print("Created factory_maps table.")

        # 2. Add layout columns to machines table
        columns = [
            ('map_id', 'INTEGER'),
            ('map_x', 'FLOAT'),
            ('map_y', 'FLOAT')
        ]

        for col_name, col_type in columns:
            try:
                c.execute(f'ALTER TABLE machines ADD COLUMN {col_name} {col_type};')
                print(f'Added {col_name} to machines')
            except sqlite3.OperationalError as e:
                print(f'Skipped {col_name}: {e}')

        db.commit()
        db.close()
        print("Done updating layout tables.")
    except Exception as e:
        print("Error:", e)

if __name__ == '__main__':
    main()
