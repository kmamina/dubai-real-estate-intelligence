"""
test_connection.py - checks Python can talk to SQL Server.

    python src/test_connection.py         # connects to the built-in 'master' database
    python src/test_connection.py --db    # connects to DubaiRealEstate and lists tables per schema
"""
import sys
from contextlib import closing

import pyodbc

import db


def main():
    print("SQL Server ODBC drivers found:", [d for d in pyodbc.drivers() if "SQL Server" in d])
    use_project_db = "--db" in sys.argv
    with closing(db.get_connection(None if use_project_db else "master")) as conn:
        cur = conn.cursor()
        cur.execute("SELECT @@SERVERNAME, DB_NAME(), CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50))")
        server, database, version = cur.fetchone()
        print(f"Connected. Server: {server} | Database: {database} | Version: {version}")
        if use_project_db:
            cur.execute("""SELECT s.name, COUNT(*) FROM sys.tables t
                           JOIN sys.schemas s ON s.schema_id = t.schema_id
                           WHERE s.name IN ('raw','stg','core','ops')
                           GROUP BY s.name ORDER BY s.name""")
            for schema, n in cur.fetchall():
                print(f"  schema {schema}: {n} tables")


if __name__ == "__main__":
    main()
