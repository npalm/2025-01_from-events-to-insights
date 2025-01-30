locals {
  data_path = "events"
}

resource "random_uuid" "s3" {}

resource "aws_s3_bucket" "data_lake" {
  bucket        = "${var.prefix}-data-lake-${random_uuid.s3.result}"
  force_destroy = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.bucket

  rule {
    id     = "Delete old files"
    status = "Enabled"

    expiration {
      days = 180
    }
  }
}

data "aws_iam_policy_document" "firehose" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${var.prefix}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose.json
}

data "aws_iam_policy_document" "firehose_s3" {
  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject"
    ]
    resources = [aws_s3_bucket.data_lake.arn, "${aws_s3_bucket.data_lake.arn}/*"]
  }
}

resource "aws_iam_role_policy" "firehose_s3" {
  name   = "${var.prefix}-s3"
  role   = aws_iam_role.firehose.name
  policy = data.aws_iam_policy_document.firehose_s3.json
}

data "aws_iam_policy_document" "firehose_log" {
  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
      "logs:CreateLogGroup"
    ]
    resources = [aws_cloudwatch_log_group.firehose_delivery_stream.arn]
  }
}

resource "aws_iam_role_policy" "firehose_log" {
  name   = "${var.prefix}-log"
  role   = aws_iam_role.firehose.name
  policy = data.aws_iam_policy_document.firehose_log.json
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3_stream" {
  name        = "${var.prefix}-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.data_lake.arn

    prefix = "${local.data_path}/github/"

    compression_format = "GZIP"
    buffering_size     = 5
    buffering_interval = 600

    processing_configuration {
      enabled = "true"

      # New line delimiter processor example
      processors {
        type = "AppendDelimiterToRecord"
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_delivery_stream.name
      log_stream_name = "github-events"
    }
  }
}

resource "aws_cloudwatch_log_group" "firehose_delivery_stream" {
  name              = "/aws/kinesisfirehose/${var.prefix}-stream"
  retention_in_days = 14
}

resource "aws_cloudwatch_event_rule" "all" {
  name           = "${var.prefix}-github-events"
  description    = "GitHub events"
  event_bus_name = module.runners.webhook.eventbridge.event_bus.name
  event_pattern  = <<EOF
{
  "source": [{
    "prefix": "github"
  }]
}
EOF
}

resource "aws_cloudwatch_event_target" "main" {
  rule           = aws_cloudwatch_event_rule.all.name
  arn            = aws_kinesis_firehose_delivery_stream.extended_s3_stream.arn
  event_bus_name = module.runners.webhook.eventbridge.event_bus.name
  role_arn       = aws_iam_role.event_rule_firehose_role.arn
}

data "aws_iam_policy_document" "event_rule_firehose_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "event_rule_firehose_role" {
  name               = "${var.prefix}-eventbridge-github"
  assume_role_policy = data.aws_iam_policy_document.event_rule_firehose_role.json
}

data "aws_iam_policy_document" "firehose_stream" {
  statement {
    actions = [
      "firehose:DeleteDeliveryStream",
      "firehose:PutRecord",
      "firehose:PutRecordBatch",
      "firehose:UpdateDestination"
    ]
    resources = [aws_kinesis_firehose_delivery_stream.extended_s3_stream.arn]
  }
}

resource "aws_iam_role_policy" "event_rule_firehose_role" {
  name   = "target-event-rule-firehose"
  role   = aws_iam_role.event_rule_firehose_role.name
  policy = data.aws_iam_policy_document.firehose_stream.json
}

resource "aws_glue_catalog_database" "github_events" {
  name = "${var.prefix}-github-events"
}

# now I need a crawler to crawl the s3 bucket and create the table
resource "aws_glue_crawler" "github_events" {
  depends_on = [aws_s3_bucket.data_lake]

  name          = "${var.prefix}-github-events"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.github_events.name
  schedule      = "cron(0 1 * * ? *)" # once a day, at 1am

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/${local.data_path}/"
  }
}

data "aws_iam_policy_document" "glue_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_role" {
  name               = "${var.prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role_policy.json
}

data "aws_iam_policy_document" "glue_s3" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:LisObjects"
    ]
    resources = [aws_s3_bucket.data_lake.arn, "${aws_s3_bucket.data_lake.arn}/*"]
  }
}

resource "aws_iam_role_policy" "glue_s3" {
  name   = "${var.prefix}-glue-s3"
  role   = aws_iam_role.glue_role.name
  policy = data.aws_iam_policy_document.glue_s3.json
}

resource "aws_iam_role_policy_attachment" "glue" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_s3_bucket" "athena_result" {
  bucket        = "${var.prefix}-athena-${random_uuid.s3.result}"
  force_destroy = true
}

resource "aws_athena_workgroup" "main" {
  name          = "${var.prefix}-workgroup"
  force_destroy = true

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_result.bucket}"
    }
  }
}
