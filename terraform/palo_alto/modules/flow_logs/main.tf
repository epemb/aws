# One log group per subnet, so each subnet's traffic is browsable on its own
# in the CloudWatch console rather than interleaved as ENI-named streams in a
# single group. CloudWatch bills on data ingested/stored, not group count, so
# splitting these costs nothing extra.
resource "aws_cloudwatch_log_group" "flow_logs" {
  for_each = var.subnets

  name              = "/aws/vpc-flow-logs/${each.key}"
  retention_in_days = lookup(var.log_retention_days, each.key, var.default_log_retention_days)
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "vpc-flow-logs-policy"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "subnet" {
  for_each = var.subnets

  subnet_id            = each.value.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[each.key].arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = {
    Name = "flow-log-${each.key}"
  }
}
