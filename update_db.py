import sqlite3
import sys

def main():
    try:
        db = sqlite3.connect('masapp.db')
        c = db.cursor()

        columns = [
            ('power_kw', 'FLOAT'),
            ('voltage_v', 'FLOAT'),
            ('current_amp', 'FLOAT'),
            ('phase', 'INTEGER'),
            ('dimensions', 'VARCHAR(100)'),
            ('weight_kg', 'FLOAT'),
            ('supplier_name', 'VARCHAR(150)'),
            ('supplier_contact', 'VARCHAR(50)'),
            ('supplier_sales', 'VARCHAR(100)'),
            ('warranty_months', 'INTEGER'),
            ('has_manual', 'BOOLEAN'),
            ('manual_file_path', 'VARCHAR(255)'),
            ('training_done', 'BOOLEAN'),
            ('intake_form_id', 'INTEGER')
        ]

        for col_name, col_type in columns:
            try:
                c.execute(f'ALTER TABLE machines ADD COLUMN {col_name} {col_type};')
                print(f'Added {col_name}')
            except sqlite3.OperationalError as e:
                print(f'Skipped {col_name}: {e}')

        db.commit()
        db.close()
        print("Done updating machines table.")
    except Exception as e:
        print("Error:", e)

if __name__ == '__main__':
    main()
