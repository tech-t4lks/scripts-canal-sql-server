import os 
from dotenv import load_dotenv
import pyodbc

load_dotenv()

def open_conn():
    conn = pyodbc.connect(
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER=DESKTOP-DBA\\TECHT4LKS;"
        f"DATABASE={os.getenv('DB_DATABASE')};"
        f"UID={os.getenv('DB_USER')};"
        f"PWD={os.getenv('DB_PASSWORD')};"
        "TrustServerCertificate=yes;"
    )
    return conn

try:
    conn = open_conn()
    print("connect successfully")
except Exception as e:
    print(f"Failed to connect: {e}")