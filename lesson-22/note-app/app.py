import os
from flask import Flask, jsonify, request
import psycopg2

app = Flask(__name__)

def get_db_connection():
    conn = psycopg2.connect(
        host=os.environ.get('DB_HOST', 'db'),
        database=os.environ.get('POSTGRES_DB', 'notes_db'),
        user=os.environ.get('POSTGRES_USER', 'user'),
        password=os.environ.get('POSTGRES_PASSWORD', 'password')
    )
    return conn

# Automatyczne tworzenie tabeli przy starcie
def init_db():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('CREATE TABLE IF NOT EXISTS notes (id SERIAL PRIMARY KEY, content TEXT NOT NULL);')
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        print("Czekam na baze danych...", e)

@app.route('/notes', methods=['GET'])
def get_notes():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT * FROM notes;')
    notes = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify(notes)

@app.route('/notes', methods=['POST'])
def add_note():
    data = request.get_json()
    content = data.get('content', '')
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('INSERT INTO notes (content) VALUES (%s);', (content,))
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({'status': 'success', 'note': content}), 201

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
