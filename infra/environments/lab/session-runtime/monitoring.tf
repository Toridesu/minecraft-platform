locals {
  monitoring_enabled    = var.enable_monitoring
  monitoring_topic_name = "${local.name_prefix}-monitoring"
  monitoring_alarm_names = [
    "${local.name_prefix}-cpu-high",
    "${local.name_prefix}-memory-high",
  ]
  monitoring_alarm_arns = local.monitoring_enabled ? [for name in local.monitoring_alarm_names :
    "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.monitoring[0].account_id}:alarm:${name}"
  ] : []
}

data "aws_caller_identity" "monitoring" {
  count = local.monitoring_enabled ? 1 : 0
}

data "aws_iam_policy_document" "monitoring_key" {
  count = local.monitoring_enabled ? 1 : 0

  statement {
    sid       = "EnableAccountIAMPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.monitoring[0].account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudWatchAlarms"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.monitoring[0].account_id]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = local.monitoring_alarm_arns
    }
  }
}

# A customer-managed key incurs charges and remains pending deletion after destroy.
resource "aws_kms_key" "monitoring" {
  count = local.monitoring_enabled ? 1 : 0

  description             = "SNS encryption for lab monitoring"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.monitoring_key[0].json

  lifecycle {
    precondition {
      condition     = var.environment == "lab"
      error_message = "The monitoring agent example is configured for the lab environment only."
    }
    precondition {
      condition     = length(trimspace(var.monitoring_email)) > 0
      error_message = "Set a private monitoring email before enabling notifications."
    }
  }
}

resource "aws_sns_topic" "monitoring" {
  count = local.monitoring_enabled ? 1 : 0

  name              = local.monitoring_topic_name
  kms_master_key_id = aws_kms_key.monitoring[0].arn
}

data "aws_iam_policy_document" "monitoring_topic" {
  count = local.monitoring_enabled ? 1 : 0

  statement {
    sid       = "AccountOwner"
    actions   = ["SNS:*"]
    resources = [aws_sns_topic.monitoring[0].arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.monitoring[0].account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudWatchAlarms"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.monitoring[0].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.monitoring[0].account_id]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = local.monitoring_alarm_arns
    }
  }
}

resource "aws_sns_topic_policy" "monitoring" {
  count = local.monitoring_enabled ? 1 : 0

  arn    = aws_sns_topic.monitoring[0].arn
  policy = data.aws_iam_policy_document.monitoring_topic[0].json
}

# The email address is sensitive but Terraform still stores it in state.
resource "aws_sns_topic_subscription" "monitoring" {
  count = local.monitoring_enabled ? 1 : 0

  topic_arn = aws_sns_topic.monitoring[0].arn
  protocol  = "email"
  endpoint  = var.monitoring_email
}

resource "aws_cloudwatch_log_group" "minecraft" {
  count = local.monitoring_enabled ? 1 : 0

  name              = "/pmp/lab/minecraft"
  retention_in_days = 1
}

data "aws_iam_policy_document" "monitoring_agent" {
  count = local.monitoring_enabled ? 1 : 0

  statement {
    sid       = "PublishLabMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["PMP/Lab"]
    }
  }
  statement {
    sid       = "DiscoverLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  statement {
    sid       = "DiscoverLabLogStreams"
    actions   = ["logs:DescribeLogStreams"]
    resources = [aws_cloudwatch_log_group.minecraft[0].arn]
  }
  statement {
    sid       = "WriteLabLogStreams"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.minecraft[0].arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "monitoring_agent" {
  count = local.monitoring_enabled ? 1 : 0

  name   = "${local.name_prefix}-monitoring-agent"
  role   = aws_iam_role.minecraft_instance.name
  policy = data.aws_iam_policy_document.monitoring_agent[0].json
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = local.monitoring_enabled ? 1 : 0

  alarm_name          = local.monitoring_alarm_names[0]
  alarm_description   = "CPU utilization is at or above 80 percent for two periods."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.monitoring[0].arn]

  dimensions = {
    InstanceId = aws_instance.minecraft.id
  }

  depends_on = [aws_sns_topic_policy.monitoring]
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count = local.monitoring_enabled ? 1 : 0

  alarm_name                = local.monitoring_alarm_names[1]
  alarm_description         = "Memory utilization is at or above 80 percent for two periods."
  namespace                 = "PMP/Lab"
  metric_name               = "mem_used_percent"
  statistic                 = "Average"
  period                    = 60
  evaluation_periods        = 2
  datapoints_to_alarm       = 2
  threshold                 = 80
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  treat_missing_data        = "missing"
  alarm_actions             = [aws_sns_topic.monitoring[0].arn]
  insufficient_data_actions = [aws_sns_topic.monitoring[0].arn]

  dimensions = {
    InstanceId = aws_instance.minecraft.id
  }

  depends_on = [aws_sns_topic_policy.monitoring]
}
