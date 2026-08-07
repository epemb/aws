output "log_group_names" {
  description = "Map of subnet name to the CloudWatch Logs group its flow logs are written to"
  value       = { for name, group in aws_cloudwatch_log_group.flow_logs : name => group.name }
}
