# DevOps Take-Home: AWS Infrastructure on ECS Fargate

Terraform code (in [`infra/`](infra/)) that provisions a containerized
application environment on AWS: a VPC with public/private/database subnets,
a public API service and a private background worker service running as
separate ECS Fargate services behind (and outside of) an ALB respectively,
an RDS Postgres database, an SQS queue, an S3 bucket, two ECR repositories,
and the IAM roles and Secrets Manager entries that tie it all together —
plus the actual application code those two services run, in
[`app/`](app/).

## Repo structure

```
.
├── infra/     # All Terraform — see infra/ for the module itself
├── app/       # Application source for the api and worker containers,
│              # see app/README.md for how to build/run each locally
└── docs/
    └── genai-usage.md   # GenAI usage log: prompts + rationale
```

## Architecture

![Architecture diagram](architecture-diagram.png)

**Traffic flow:** Internet → ALB (public subnets) → **API** ECS Fargate
tasks (private app subnets, `awsvpc` networking) → RDS (private database
subnets). The **worker** service runs in the same private app subnets but
sits behind its own security group with **no ingress rules at all** — it is
not attached to the ALB target group and is not reachable from the ALB, the
internet, or the API service; it only pulls jobs from SQS. Both services
reach the internet (e.g. for ECR image pulls) through a NAT Gateway; nothing
in the app or database tiers has a public IP.

## Resources provisioned

| Category | Resources |
|---|---|
| Networking | VPC, 2 public + 2 private + 2 database subnets across 2 AZs, IGW, NAT Gateway, route tables, 4 security groups (ALB, ECS API, ECS worker, RDS) |
| Compute | ECS cluster, **two** Fargate task definitions and **two** ECS services (`api`, `worker`), Application Load Balancer, target group, HTTP listener (API only — the worker is not attached to the ALB) |
| Registry | Two ECR repositories, `api` and `worker` (image scanning on push, lifecycle policy retaining last 10 images each) |
| Data | RDS PostgreSQL instance (private, encrypted, in its own subnet group), SQS queue + dead-letter queue |
| Storage | S3 bucket (versioned, SSE-encrypted, public access blocked) |
| Secrets | Secrets Manager secret holding the generated RDS master credentials, injected into both ECS task definitions via the `secrets` block |
| IAM | One shared ECS task execution role (image pull, log write, secret read) plus **two distinct task roles** — `ecs_task_api` (SQS send-only, S3 read/write) and `ecs_task_worker` (SQS receive/delete on the queue and DLQ, S3 read/write/delete) — each scoped to only what that service needs |

### API vs. worker services

| | API service | Worker service |
|---|---|---|
| Reachable from ALB? | Yes — target group + listener | No — not registered with any target group |
| Public/private | Public (via ALB, tasks themselves stay in private subnets) | Private — no ingress rule exists on its security group |
| Security group | `ecs_api` — ingress from ALB SG on `container_port` only | `ecs_worker` — no ingress rules at all |
| IAM task role | `ecs_task_api` — `sqs:SendMessage`/`GetQueueUrl`/`GetQueueAttributes`, S3 get/put/list | `ecs_task_worker` — `sqs:ReceiveMessage`/`DeleteMessage`/`GetQueueAttributes`/`GetQueueUrl` on queue + DLQ, S3 get/put/delete/list |
| Task definition | `aws_ecs_task_definition.api` (`var.api_image`, container port exposed) | `aws_ecs_task_definition.worker` (`var.worker_image`, no port mappings) |
| Scaling | `var.api_desired_count` (default 2) | `var.worker_desired_count` (default 1) |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- An AWS account and credentials configured (e.g. via `aws configure`,
  environment variables, or an SSO profile) with permissions to create the
  resources above
- (Optional) Docker, if you intend to build and push the real application
  images in `app/` to the ECR repositories this creates

This code was written and validated with Terraform v1.13.0. No AWS
credentials are required to run `terraform fmt` or `terraform validate`;
credentials are only needed for `terraform plan`/`apply`. All Terraform
commands below are run from inside `infra/`.

## Usage

```bash
cd infra

# Review/adjust variables (region, sizing, CIDRs, etc.)
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

By default both ECS services run public placeholder images (`api_image` =
`public.ecr.aws/nginx/nginx:latest`, `worker_image` =
`public.ecr.aws/docker/library/busybox:latest`) so the stack is deployable
end-to-end without building anything first. To run the real app code in
`app/` instead:

```bash
# From the repo root, after `terraform apply` (run from infra/) has
# created the ECR repos:
aws ecr get-login-password --region <region> | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com

docker build -t <ecr_api_repository_url>:latest ./app/api
docker push <ecr_api_repository_url>:latest

docker build -t <ecr_worker_repository_url>:latest ./app/worker
docker push <ecr_worker_repository_url>:latest

# Then set api_image = "<ecr_api_repository_url>:latest" and
# worker_image = "<ecr_worker_repository_url>:latest" in
# infra/terraform.tfvars and re-apply (from infra/).
```

See [`app/README.md`](app/README.md) for what each service does, what
environment variables it expects, and how to run it outside of ECS for
local testing.

Grab the load balancer URL from the outputs (from `infra/`):

```bash
terraform output alb_dns_name
```

## Cleanup

```bash
cd infra
terraform destroy
```

RDS is created with `skip_final_snapshot = true` by default (see
`db_skip_final_snapshot` in `infra/variables.tf`) so `destroy` doesn't hang
waiting on a snapshot; flip that to `false` for anything beyond a throwaway
environment.

## Notable design decisions / trade-offs

- **Single shared NAT Gateway by default** (`single_nat_gateway = true`) to
  keep cost down for a take-home exercise; set it to `false` for one NAT
  Gateway per AZ in a real HA deployment.
- **HTTP-only ALB listener.** No ACM certificate/domain was provided, so
  there's no HTTPS listener. Adding one is a matter of an
  `aws_acm_certificate` (or importing an existing cert) plus a 443
  `aws_lb_listener` and redirecting 80 → 443.
- **RDS credentials** are generated with `random_password`, stored in
  Secrets Manager, and injected into the ECS task via the task definition's
  `secrets` block (`valueFrom` referencing the secret ARN) rather than as
  plaintext environment variables.
- **Root module, flat files** (`infra/vpc.tf`, `infra/ecs.tf`,
  `infra/rds.tf`, etc.) rather than child modules — appropriate for a
  single-environment take-home; a multi-environment setup would extract
  these into reusable modules under `infra/modules/`.
- **Fargate tasks have no public IP** and reach ECR/Secrets
  Manager/CloudWatch through the NAT Gateway; VPC endpoints would remove
  that NAT dependency for AWS API traffic in a cost- or latency-sensitive
  production setup.
- **API and worker are separate ECS services, each with its own security
  group and IAM task role**, rather than one service doing both jobs. The
  worker's security group has no ingress rules at all — it isn't attached
  to any ALB target group, so there is no network path into it from the
  ALB, the internet, or even the API service. Splitting the IAM task roles
  means a compromised API container can enqueue work but can't drain or
  delete queue messages, and a compromised worker container was never
  reachable from the internet in the first place.
- **A shared ECS task execution role** (image pull, log write, DB-secret
  read) is used by both task definitions, since that role only grants
  ECS-agent-level permissions, not application permissions — the
  security-relevant split is at the task role level, which is where each
  service's actual AWS API access is scoped.

## Repo layout

```
.
├── infra/                       # Terraform root module
│   ├── versions.tf              # Terraform + provider version constraints
│   ├── variables.tf             # Input variables
│   ├── vpc.tf                   # VPC, subnets, routing, security groups
│   ├── alb.tf                   # Application Load Balancer (API target group + listener)
│   ├── ecr.tf                   # ECR repositories (api, worker)
│   ├── ecs.tf                   # ECS cluster + api/worker task definitions and services
│   ├── rds.tf                   # RDS PostgreSQL instance
│   ├── sqs.tf                   # SQS queue + DLQ
│   ├── s3.tf                    # S3 bucket
│   ├── secrets.tf               # Secrets Manager secret + generated password
│   ├── iam.tf                   # IAM roles/policies for ECS tasks (shared execution role, api/worker task roles)
│   ├── outputs.tf                # Output values
│   ├── terraform.tfvars.example  # Example variable values
│   └── .terraform.lock.hcl       # Provider version lock (committed)
├── app/                          # Application source
│   ├── api/                      # Flask API: POST /jobs, GET /health
│   │   ├── app.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   ├── worker/                   # SQS-polling background worker
│   │   ├── worker.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── README.md                 # Build/run instructions, env var reference
├── docs/
│   └── genai-usage.md            # GenAI usage log: prompts + rationale
└── README.md
```
