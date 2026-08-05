# GenAI Usage Log

I used Claude Code CLI throughout this assignment, mainly to check my
system's software (Terraform, Docker, AWS CLI configuration), to generate
and validate the Terraform code, and to help me understand the
architecture and process flow before writing the README. Below are the
main prompts I used and why.

## Prompts used

**1. Checking my environment was ready**

> "Check if Terraform is installed on this machine. If not, help me install
> it. Then confirm `terraform version` works."

I used this to confirm Terraform, Docker, and my AWS CLI configuration
were all correctly set up before generating or running any code — rather
than assuming my machine was ready and hitting setup errors partway
through.

**2. Validating the Terraform code**

> "Run `terraform fmt -check -recursive` and `terraform validate` on this
> configuration and tell me if anything fails or needs fixing."

I used this to check that my Terraform was syntactically correct and
properly formatted against the assignment's requirement that it pass both
`fmt` and `validate`, and to catch any issues before I considered the code
ready to review further.

**3. Fixing the architecture to match the requirements**

> "The current setup only has one ECS service. The assignment requires a
> separate API service and a separate background worker service, each not
> publicly accessible where required, with their own security groups and
> IAM roles. Please refactor this into api and worker."

I caught that the first version didn't fully satisfy the requirement for
separate API/worker containers, and asked for this to be corrected — this
also helped me understand *why* the two services need separate security
groups and IAM roles (least privilege, and the worker having no inbound
access at all).

**4. Understanding the process flow**

> "Walk me through how data flows through this system — from a request
> hitting the API, to the worker picking up a job, to how secrets and
> permissions fit in at each step."

I used this to build a clear mental model of the full request path (API →
SQS → worker → RDS/S3) and how Secrets Manager and IAM roles apply at each
stage, so I could explain the design decisions in the README myself
rather than just accepting generated output.

## Verification I did, not just generated

Before considering this complete, I ran and reviewed the output of:

```bash
terraform fmt -check -recursive
terraform validate
```

I also deployed this to a real AWS account (`eu-central-1`) to confirm it
works end to end, and fixed two real issues along the way: missing IAM
permissions on my AWS user, and an RDS engine version that wasn't
available in the region. Both were resolved and re-applied successfully.
