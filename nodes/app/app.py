"""SecLab application tier: a small read-only analytics API.

Runs under gunicorn, bound to 127.0.0.1:5000. It is never exposed directly:
nginx on the same host terminates (mutual) TLS and relays requests to it.
Database settings come from environment variables set by start.sh.
"""
import os

import psycopg2
import psycopg2.extras
from flask import Flask, jsonify, request

app = Flask(__name__)


def get_db():
    """Open a database connection. sslmode=verify-full means: encrypt, check the
    server certificate against our root CA, and check that its name matches."""
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "db.seclab.test"),
        dbname="portal",
        user="portal",
        password=os.environ["DB_PASSWORD"],
        sslmode=os.environ.get("DB_SSLMODE", "verify-full"),
        sslrootcert=os.environ.get("DB_SSLROOTCERT", "/etc/seclab/root.crt"),
        connect_timeout=3,
    )


@app.get("/api/health")
def health():
    return jsonify(status="ok")


@app.get("/api/summary")
def summary():
    """Aggregate query: number of orders and revenue per region."""
    with get_db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "SELECT region, count(*) AS orders, round(sum(amount), 2)::float AS revenue "
            "FROM orders GROUP BY region ORDER BY region"
        )
        return jsonify(regions=cur.fetchall())


@app.get("/api/customers")
def customers():
    """Customer records for one region. The %s placeholder makes this a
    parameterised query, so user input can never be executed as SQL."""
    region = request.args.get("region", "APAC")
    with get_db() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            "SELECT id, name, email, region FROM customers WHERE region = %s ORDER BY id LIMIT 20",
            (region,),
        )
        return jsonify(customers=cur.fetchall())
