data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# Task execution role: used by the ECS agent to pull images, write logs,
# and resolve secrets referenced in the task definition.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = {
    Name = "${local.name}-ecs-task-execution"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution_secrets" {
  statement {
    sid       = "ReadDbCredentials"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name   = "${local.name}-ecs-task-execution-secrets"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_execution_secrets.json
}

# ---------------------------------------------------------------------------
# API task role: used by the public-facing API service. It enqueues jobs
# for the worker to pick up but does not consume the queue itself, and
# handles user-facing object uploads/downloads.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task_api" {
  name               = "${local.name}-ecs-task-api"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = {
    Name = "${local.name}-ecs-task-api"
  }
}

data "aws_iam_policy_document" "ecs_task_api" {
  statement {
    sid = "SqsEnqueueOnly"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.app.arn]
  }

  statement {
    sid = "S3Access"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.app.arn,
      "${aws_s3_bucket.app.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_api" {
  name   = "${local.name}-ecs-task-api"
  role   = aws_iam_role.ecs_task_api.id
  policy = data.aws_iam_policy_document.ecs_task_api.json
}

# ---------------------------------------------------------------------------
# Worker task role: used by the private background worker service. It
# consumes and deletes messages from the queue (including the DLQ, for
# inspection/reprocessing) and does the S3 read/write/delete work of
# actually processing a job.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task_worker" {
  name               = "${local.name}-ecs-task-worker"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = {
    Name = "${local.name}-ecs-task-worker"
  }
}

data "aws_iam_policy_document" "ecs_task_worker" {
  statement {
    sid = "SqsConsume"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [
      aws_sqs_queue.app.arn,
      aws_sqs_queue.app_dlq.arn,
    ]
  }

  statement {
    sid = "S3Access"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.app.arn,
      "${aws_s3_bucket.app.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_worker" {
  name   = "${local.name}-ecs-task-worker"
  role   = aws_iam_role.ecs_task_worker.id
  policy = data.aws_iam_policy_document.ecs_task_worker.json
}
