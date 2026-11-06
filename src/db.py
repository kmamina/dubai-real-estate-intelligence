"""
db.py - one place that knows how to connect to SQL Server.

Connection details come from a local `.env` file (never committed to Git) or from
environment variables. We use Windows Authentication, so NO password is stored anywhere.
"""
import os

import pyodbc

import config


def _read_env_file():
    values = {}
    env_path = config.PROJECT_ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip()
    return values


def _setting(name, default):
    return os.environ.get(name) or _read_env_file().get(name) or default


def pick_driver():
    """Prefer the newest 'ODBC Driver NN for SQL Server'; fall back to the old Windows one."""
    drivers = [d for d in pyodbc.drivers() if "SQL Server" in d]
    modern = sorted([d for d in drivers if d.startswith("ODBC Driver")], reverse=True)
    if modern:
        return modern[0]
    if drivers:
        return drivers[0]
    raise RuntimeError("No SQL Server ODBC driver found. Install 'ODBC Driver 18 for SQL Server'.")


def get_connection(database=None, autocommit=False):
    server = _setting("DRE_SQL_SERVER", "localhost")
    database = database or _setting("DRE_SQL_DATABASE", "DubaiRealEstate")
    driver = pick_driver()
    conn_str = (f"DRIVER={{{driver}}};SERVER={server};DATABASE={database};"
                "Trusted_Connection=yes;TrustServerCertificate=yes;")
    return pyodbc.connect(conn_str, autocommit=autocommit, timeout=10)
