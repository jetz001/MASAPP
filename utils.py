import logging
import configparser
import os
from pathlib import Path

# Load Configuration
config = configparser.ConfigParser()
config_path = Path(__file__).parent / 'config.ini'
if config_path.exists():
    config.read(config_path)
else:
    # Default fallback if config is missing
    config.add_section('General')
    config.set('General', 'log_level', 'INFO')
    config.set('General', 'log_file', 'masapp.log')
    config.add_section('Database')
    config.set('Database', 'url', 'sqlite:///masapp_fallback.db')

def setup_logging():
    log_level_str = config.get('General', 'log_level', fallback='INFO')
    log_file = config.get('General', 'log_file', fallback='masapp.log')
    
    numeric_level = getattr(logging, log_level_str.upper(), logging.INFO)
    
    logging.basicConfig(
        level=numeric_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger("MASAPP")

logger = setup_logging()
