resource "aws_sqs_queue" "app_dlq" {
  name                      = "${local.name}-app-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name = "${local.name}-app-dlq"
  }
}

resource "aws_sqs_queue" "app" {
  name                       = "${local.name}-app-queue"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.app_dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Name = "${local.name}-app-queue"
  }
}
