# GenAI Usage Log

This assignment was built with assistance from Claude (Anthropic), used as a
pair-programming/CLI agent (Claude Code) inside this repository. This
document records the prompts that drove the work and the rationale behind
the resulting design decisions, as required by the assignment instructions.

## Tooling

- **Model/tool:** Claude (Claude Code CLI), Sonnet 5
- **Mode of use:** Interactive session in the repo working directory,
  generating Terraform files directly, running `terraform fmt`/`init`/`validate`
  to check its own output, and writing this documentation.

## Prompt log

### 1. Environment setup

> "First, check if Terraform is installed on this machine. If not, help me
> install it via Chocolatey or the official Windows binary. Then confirm
> `terraform version` works."

**Outcome:** Terraform v1.13.0 was already installed; verified with
`terraform version` rather than reinstalling. No changes made.

### 2. Scoping the infrastructure

> "It requires Terraform code (AWS: VPC, ECS Fargate, RDS/SQS, S3, ECR,
> Secrets Manager, ALB, IAM) that must pass `terraform fmt` and `terraform
> validate`, plus a README and an architecture diagram, submitted as a git
> repo."

Before generating code, Claude asked clarifying questions rather than
guessing, since several reasonable interpretations existed:

- Root module vs. reusable child modules for structure
- Whether a real application image existed to containerize, or a placeholder
  was needed
- Whether RDS and SQS were alternatives or both were required (the prompt
  listed them as `RDS/SQS`)
- Diagram format (Mermaid vs. exported image)

**Rationale for asking instead of assuming:** these choices materially
change the shape of the deliverable (file layout, whether a Dockerfile is
needed, resource count), and getting them wrong would mean redoing
significant work. The answers given — root module, placeholder container
image, both RDS and SQS, Mermaid diagram in the README — are reflected
throughout the code and are called out explicitly here so a reviewer can see
they were deliberate choices, not defaults Claude picked unilaterally.

### 3. Splitting the ECS workload into api/worker services

> "The current setup only has one ECS service. The assignment requires a
> separate API service (public, behind the ALB) and a separate background
> worker service (private, no ALB, not publicly accessible, pulling jobs
> from SQS) - two distinct task definitions and two distinct ECS services,
> each with its own security group and IAM task role. Please refactor
> ecs.tf to split these into api and worker, matching how SQS, IAM, and the
> security groups already reference them separately."

The original single `app` ECS service was replaced with two independent
services, `api` and `worker`, each with its own task definition, security
group, and IAM task role — touching `ecs.tf`, `vpc.tf` (security groups),
`iam.tf` (task roles), `ecr.tf` (one repo per service, since each service
now ships a different image), `alb.tf` (target group renamed to make clear
it's API-only), `outputs.tf`, `variables.tf`, `terraform.tfvars.example`,
and the README.

**Rationale for the specific split:**

- The **worker's security group has no ingress rules at all**, rather than
  a narrowed ingress rule. Since the worker is never supposed to receive
  inbound traffic from anything (not the ALB, not the API, not the
  internet), the correct security group is one with zero ingress rules —
  making "not publicly accessible" a property enforced by the network
  layer, not just by omitting an ALB attachment.
- **IAM task roles diverge by what each service actually does**: the API
  role gets `sqs:SendMessage`/`GetQueueUrl`/`GetQueueAttributes` (enqueue
  only — it has no reason to read or delete jobs), while the worker role
  gets `sqs:ReceiveMessage`/`DeleteMessage`/`GetQueueAttributes`/`GetQueueUrl`
  on both the main queue and the DLQ (consume, and inspect failed jobs). A
  single shared "SQS access" role would have given the public-facing
  service permission to drain or delete jobs it has no business touching.
- **The ECS task execution role stayed shared** rather than being split
  too. That role only grants ECS-agent-level permissions (pull from ECR,
  write to CloudWatch, resolve the one DB secret) — it never runs
  application code, so there's no privilege-separation benefit to
  duplicating it. The user's ask was specifically about the *task* role,
  and the code now reflects that distinction explicitly (`ecs_task_api` /
  `ecs_task_worker` vs. one `ecs_task_execution`).
- **Two ECR repositories instead of one.** This wasn't explicitly requested,
  but follows directly from having two independently-built images with
  different lifecycles — a single shared repo would force the API and
  worker images to share tag history and lifecycle-policy counts for no
  benefit.
- **`worker_image` defaults to `busybox`, not `nginx`.** The worker has no
  listening port and isn't behind a load balancer, so a webserver
  placeholder wouldn't reflect what it actually needs to do (idle/poll,
  not serve HTTP); a minimal shell image is a closer stand-in for "runs a
  polling loop" until a real worker image is supplied.

## Design rationale for generated code

These are decisions made while generating the Terraform, with the reasoning
behind each — included here because "why this shape" isn't always evident
from the code alone:

- **Three-tier subnet layout (public / private-app / private-db)** instead
  of a two-tier layout. A dedicated database subnet tier keeps RDS fully
  isolated from the app tier's route table and security group, which is
  closer to how this would be built for a real workload and makes the
  security-group chain (ALB → ECS → RDS) easy to audit at a glance.
- **Security groups reference each other by ID** (`aws_security_group.alb.id`
  as the source for the API service's SG, the API and worker SGs as the
  sources for the RDS SG) rather than by CIDR block. This means only traffic
  that has actually passed through the previous tier is allowed further in,
  regardless of subnet numbering. (Originally a single `ecs_service` SG
  before the api/worker split — see "Splitting the ECS workload into
  api/worker services" above.)
- **DB credentials generated with `random_password` and stored in Secrets
  Manager**, then injected into the ECS task definition via the `secrets`
  block (`valueFrom` = secret ARN + JSON key), instead of passing a password
  variable through Terraform state as a plain container environment
  variable. This was chosen specifically because the assignment calls out
  Secrets Manager as a required resource, and because it avoids the
  password appearing in the task definition's `environment` list (which is
  visible via the ECS console/API to anyone with task-definition read
  access).
- **Execution role vs. task role(s)**, following the standard ECS pattern:
  the execution role is scoped to what the ECS *agent* needs (pull from
  ECR, write logs, read the one secret it's told to resolve) and is shared
  across services; the task role is scoped to what the *application code*
  needs at runtime and is per-service. This started as one shared task role
  and was later split into `ecs_task_api` / `ecs_task_worker` when the ECS
  workload itself was split into separate services — see "Splitting the ECS
  workload into api/worker services" above for the rationale on why those
  two roles diverge.
- **SQS queue paired with a dead-letter queue** with a redrive policy
  (`maxReceiveCount = 5`), rather than a single queue, so poison messages
  don't loop indefinitely — a small addition beyond the literal "add an SQS
  queue" requirement, justified because a queue without a DLQ is generally
  considered incomplete for anything beyond a toy example.
- **Single shared NAT Gateway by default**, exposed as a
  `single_nat_gateway` variable rather than hardcoded either way. Multi-AZ
  NAT is the "correct" HA answer but roughly doubles NAT cost for a stack
  that's being stood up for a take-home review; making it a variable lets a
  reviewer flip one flag to see the HA version without a code change.
- **Placeholder container image** (`public.ecr.aws/nginx/nginx:latest`) as
  the `app_image` default, with the ECR repository still created and its
  URL exposed as an output. This keeps `terraform apply` deployable
  end-to-end (ALB → ECS → healthy target) without requiring an application
  codebase, while leaving a clear path (documented in the README) to swap
  in a real image.
- **No HTTPS listener.** Adding one requires a domain and an ACM
  certificate, neither of which exists for this exercise. Documented as a
  known gap in the README rather than faked with a self-signed cert or
  silently omitted.

## Verification performed (not just generated)

Claude ran, rather than only asserted, the following before considering the
code complete:

```bash
terraform fmt -recursive
terraform fmt -check -recursive   # exit 0
terraform init -backend=false
terraform validate                 # "Success! The configuration is valid."
```

`terraform plan`/`apply` were **not** run, since that requires real AWS
credentials and would provision billable resources — left to whoever runs
this against their own AWS account.

## Human review

All generated Terraform was reviewed for the security-relevant properties
called out above (least-privilege IAM, no public database/app subnets,
secrets kept out of plain environment variables, S3 public access blocked)
before being committed. Variable defaults (region, instance sizes, CIDR
ranges) should be reviewed against the actual target AWS account before
applying in anything other than a scratch environment.
