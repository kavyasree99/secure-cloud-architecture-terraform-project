# Application code

Two small Python services matching the `api` and `worker` ECS services
defined in `../infra/`:

- **`api/`** — Flask app. `POST /jobs` writes a row to Postgres and sends a
  message to SQS; `GET /health` is the ALB health check target.
- **`worker/`** — long-polls SQS in a loop, does a trivial "process" step
  (stamps the matching Postgres row with `processed_at`), and only deletes
  the SQS message on success.

Both are intentionally minimal — a couple of pinned dependencies each, no
framework beyond Flask for the API — since the point of this repo is the
infrastructure, not the application.

## Environment variables

Both services read the same set of variables, matching what
`infra/ecs.tf` injects into the task definitions (plain env vars from
`environment`, credentials from `secrets` backed by Secrets Manager):

| Variable | Source in `infra/` | Used by |
|---|---|---|
| `AWS_REGION` | `environment` block | both |
| `APP_SQS_QUEUE_URL` | `environment` block (`aws_sqs_queue.app.url`) | both |
| `DB_HOST` | `environment` block (`aws_db_instance.main.address`) | both |
| `DB_PORT` | `environment` block (default `5432` if unset) | both |
| `DB_NAME` | `environment` block | both |
| `DB_USERNAME` | `secrets` block (Secrets Manager `username`) | both |
| `DB_PASSWORD` | `secrets` block (Secrets Manager `password`) | both |
| `PORT` | not set by Terraform; defaults to `8080` | api only |
| `SQS_WAIT_TIME_SECONDS` | not set by Terraform; defaults to `20` | worker only |
| `SQS_VISIBILITY_TIMEOUT` | not set by Terraform; defaults to `60`, matching `infra/sqs.tf` | worker only |
| `SQS_MAX_MESSAGES` | not set by Terraform; defaults to `5` | worker only |

`APP_S3_BUCKET` is also injected by Terraform for future use but neither
service currently touches S3.

## Running locally

Both need network access to a Postgres instance and an SQS queue — either
point them at the real AWS resources from `infra/` (after `terraform
apply`, using `terraform output` and short-lived local AWS credentials), or
run against local equivalents (e.g. `postgres` in Docker and
[ElasticMQ](https://github.com/softwaremill/elasticmq) or a real low-traffic
AWS SQS queue in a sandbox account). Nothing in this repo stands up either
of those for you.

### API

```bash
cd app/api
python -m venv .venv && . .venv/Scripts/activate   # or source .venv/bin/activate on macOS/Linux
pip install -r requirements.txt

export AWS_REGION=us-east-1
export APP_SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/<account-id>/<queue-name>
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=appdb
export DB_USERNAME=app_admin
export DB_PASSWORD=<password>

python app.py
# Health check:
curl http://localhost:8080/health
# Create a job:
curl -X POST http://localhost:8080/jobs -H 'Content-Type: application/json' -d '{"foo": "bar"}'
```

To build/run the container image instead (build only — do not push unless
you intend to deploy it):

```bash
cd app/api
docker build -t api:local .
docker run --rm -p 8080:8080 \
  -e AWS_REGION -e APP_SQS_QUEUE_URL -e DB_HOST -e DB_PORT -e DB_NAME \
  -e DB_USERNAME -e DB_PASSWORD \
  api:local
```

### Worker

```bash
cd app/worker
python -m venv .venv && . .venv/Scripts/activate
pip install -r requirements.txt

export AWS_REGION=us-east-1
export APP_SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/<account-id>/<queue-name>
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=appdb
export DB_USERNAME=app_admin
export DB_PASSWORD=<password>

python worker.py
```

Or as a container:

```bash
cd app/worker
docker build -t worker:local .
docker run --rm \
  -e AWS_REGION -e APP_SQS_QUEUE_URL -e DB_HOST -e DB_PORT -e DB_NAME \
  -e DB_USERNAME -e DB_PASSWORD \
  worker:local
```

The worker needs AWS credentials available in its environment (or an
instance/task role, when running on ECS) with `sqs:ReceiveMessage`,
`sqs:DeleteMessage`, and `sqs:GetQueueAttributes` on the queue — exactly
what `infra/iam.tf`'s `ecs_task_worker` role grants in AWS.

## Deploying

Build and push are deliberately left to you — see the root `README.md`'s
"Usage" section for the `docker build` / `docker push` / `terraform apply`
sequence once you have real images in ECR.
