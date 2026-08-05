import json
import logging
import os

import boto3
import psycopg2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("worker")

AWS_REGION = os.environ.get("AWS_REGION", "eu-central-1")
SQS_QUEUE_URL = os.environ["APP_SQS_QUEUE_URL"]

DB_HOST = os.environ["DB_HOST"]
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ["DB_NAME"]
DB_USERNAME = os.environ["DB_USERNAME"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

# Long-poll wait time; keep this close to the SQS max (20s) to minimize
# empty-receive API calls while idle.
WAIT_TIME_SECONDS = int(os.environ.get("SQS_WAIT_TIME_SECONDS", "20"))
VISIBILITY_TIMEOUT = int(os.environ.get("SQS_VISIBILITY_TIMEOUT", "60"))
MAX_MESSAGES = int(os.environ.get("SQS_MAX_MESSAGES", "5"))

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


def process_job(job_id):
    """Trivial processing step: stamp the matching row as processed."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE jobs SET status = 'processed', processed_at = now() "
                "WHERE id = %s",
                (job_id,),
            )
            if cur.rowcount == 0:
                raise ValueError(f"no job row found for id={job_id}")
        conn.commit()


def handle_message(message):
    body = json.loads(message["Body"])
    job_id = body["job_id"]
    logger.info("processing job %s", job_id)
    process_job(job_id)
    logger.info("finished job %s", job_id)


def poll_forever():
    logger.info("worker starting, polling %s", SQS_QUEUE_URL)
    while True:
        response = sqs.receive_message(
            QueueUrl=SQS_QUEUE_URL,
            MaxNumberOfMessages=MAX_MESSAGES,
            WaitTimeSeconds=WAIT_TIME_SECONDS,
            VisibilityTimeout=VISIBILITY_TIMEOUT,
        )

        for message in response.get("Messages", []):
            try:
                handle_message(message)
            except Exception:
                # Don't delete on failure: leave the message in the queue
                # so it becomes visible again once the visibility timeout
                # expires. After maxReceiveCount attempts, SQS's redrive
                # policy (see infra/sqs.tf) moves it to the DLQ for us.
                logger.exception(
                    "failed to process message %s, leaving it in the queue"
                    " for retry",
                    message.get("MessageId"),
                )
                continue

            sqs.delete_message(
                QueueUrl=SQS_QUEUE_URL,
                ReceiptHandle=message["ReceiptHandle"],
            )


if __name__ == "__main__":
    poll_forever()
