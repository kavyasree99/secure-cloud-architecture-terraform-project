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
  as the source for the ECS SG, `aws_security_group.ecs_service.id` as the
  source for the RDS SG) rather than by CIDR block. This means only traffic
  that has actually passed through the previous tier is allowed further in,
  regardless of subnet numbering.
- **DB credentials generated with `random_password` and stored in Secrets
  Manager**, then injected into the ECS task definition via the `secrets`
  block (`valueFrom` = secret ARN + JSON key), instead of passing a password
  variable through Terraform state as a plain container environment
  variable. This was chosen specifically because the assignment calls out
  Secrets Manager as a required resource, and because it avoids the
  password appearing in the task definition's `environment` list (which is
  visible via the ECS console/API to anyone with task-definition read
  access).
- **Two IAM roles per ECS task** (execution role vs. task role) rather than
  one combined role, following the standard ECS pattern: the execution role
  is scoped to what the ECS *agent* needs (pull from ECR, write logs, read
  the one secret it's told to resolve); the task role is scoped to what the
  *application code* needs at runtime (SQS send/receive, S3 get/put/list on
  its own bucket only). Splitting them keeps each policy minimal and makes
  it obvious which permissions are agent-level vs. app-level during review.
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
