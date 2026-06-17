data "archive_file" "asg_notify_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/asg_notify.py"
  output_path = "${path.module}/lambda/asg_notify.zip"
}

resource "aws_iam_role" "asg_notify_lambda_role" {
  name = "${local.name_prefix}-asg-notify-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "asg_notify_lambda_basic" {
  role       = aws_iam_role.asg_notify_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "asg_notify" {
  function_name = "${local.name_prefix}-asg-notify"
  role          = aws_iam_role.asg_notify_lambda_role.arn
  handler       = "asg_notify.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.asg_notify_lambda_zip.output_path
  source_code_hash = data.archive_file.asg_notify_lambda_zip.output_base64sha256

  timeout = 10

  environment {
    variables = {
      TELEGRAM_BOT_TOKEN  = var.telegram_bot_token
      TELEGRAM_CHAT_ID    = var.telegram_chat_id
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
    }
  }
}

resource "aws_cloudwatch_event_rule" "asg_events" {
  name        = "${local.name_prefix}-asg-events"
  description = "Detect Auto Scaling launch and terminate events"

  event_pattern = jsonencode({
    source = ["aws.autoscaling"]

    detail-type = [
      "EC2 Instance Launch Successful",
      "EC2 Instance Launch Unsuccessful",
      "EC2 Instance Terminate Successful",
      "EC2 Instance Terminate Unsuccessful"
    ]
  })
}

resource "aws_cloudwatch_event_target" "asg_events_to_lambda" {
  rule      = aws_cloudwatch_event_rule.asg_events.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.asg_notify.arn
}

resource "aws_lambda_permission" "allow_eventbridge_asg" {
  statement_id  = "AllowExecutionFromEventBridgeASG"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asg_notify.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg_events.arn
}