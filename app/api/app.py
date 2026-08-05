import json
import logging
import os
import time

import boto3
import psycopg2
from flask import Flask, jsonify, request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("api")

app = Flask(__name__)

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
SQS_QUEUE_URL = os.environ["APP_SQS_QUEUE_URL"]

DB_HOST = os.environ["DB_HOST"]
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ["DB_NAME"]
DB_USERNAME = os.environ["DB_USERNAME"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

sqs = boto3.client("sqs", region_name=AWS_REGION)


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USERNAME,
        password=DB_PASSWORD,
        connect_timeout=5,
    )


def ensure_schema(retries=5, delay_seconds=3):
    """Create the jobs table if it doesn't exist yet.

    Retries on startup since the API container can come up before RDS is
    reachable (e.g. right after `terraform apply`).
    """
    last_error = None
    for attempt in range(1, retries + 1):
        try:
            with get_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        CREATE TABLE IF NOT EXISTS jobs (
                            id BIGSERIAL PRIMARY KEY,
                            payload JSONB NOT NULL,
                            status TEXT NOT NULL DEFAULT 'pending',
                            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                            processed_at TIMESTAMPTZ
                        )
                        """
                    )
                conn.commit()
            return
        except psycopg2.OperationalError as exc:
            last_error = exc
            logger.warning(
                "database not ready yet (attempt %s/%s): %s", attempt, retries, exc
            )
            time.sleep(delay_seconds)
    raise RuntimeError("could not reach database on startup") from last_error


@app.route("/health", methods=["GET"])
def health():
    return jsonify(status="ok"), 200


@app.route("/jobs", methods=["POST"])
def create_job():
    payload = request.get_json(silent=True)
    if payload is None:
        return jsonify(error="request body must be valid JSON"), 400

    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO jobs (payload) VALUES (%s) RETURNING id",
                    (json.dumps(payload),),
                )
                job_id = cur.fetchone()[0]
            conn.commit()
    except psycopg2.Error:
        logger.exception("failed to write job to Postgres")
        return jsonify(error="failed to persist job"), 500

    message_body = json.dumps({"job_id": job_id, "payload": payload})
    try:
        sqs.send_message(QueueUrl=SQS_QUEUE_URL, MessageBody=message_body)
    except Exception:
        logger.exception("failed to enqueue job %s", job_id)
        return (
            jsonify(error="job persisted but failed to enqueue", job_id=job_id),
            502,
        )

    return jsonify(job_id=job_id), 200


ensure_schema()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
