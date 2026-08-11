import os
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

def get_conn():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "db"),
        dbname=os.environ.get("DB_NAME", "hw21"),
        user=os.environ.get("DB_USER", "postgres"),
        password=os.environ["DB_PASSWORD"],
    )

@app.route("/")
def index():
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT version();")
        version = cur.fetchone()[0]
    return jsonify(status="ok", db_version=version)

@app.route("/add")
def add():
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("CREATE TABLE IF NOT EXISTS visits (id SERIAL PRIMARY KEY, ts TIMESTAMP DEFAULT now());")
        cur.execute("INSERT INTO visits DEFAULT VALUES RETURNING id;")
        new_id = cur.fetchone()[0]
    return jsonify(inserted_id=new_id)

@app.route("/list")
def list_visits():
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, ts FROM visits ORDER BY id;")
        rows = [{"id": r[0], "ts": r[1].isoformat()} for r in cur.fetchall()]
    return jsonify(count=len(rows), visits=rows)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
