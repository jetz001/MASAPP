import os
import sys
from utils import logger
# Assuming we run this from inside MASAPP:
from models import engine, Base

def initialize_database():
    logger.info("Initializing database schema...")
    if engine is None:
        logger.error("No database engine available. Check your config.ini connection string.")
        sys.exit(1)
        
    try:
        # Create all tables
        Base.metadata.create_all(bind=engine)
        logger.info("Database schema created successfully.")
    except Exception as e:
        logger.error(f"Error creating database schema: {e}")
        sys.exit(1)

if __name__ == "__main__":
    initialize_database()
