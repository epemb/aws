variable "subnets" {
  description = "Map of subnet name to its attributes, from the network module's outputs. A flow log is created for every entry."
  type = map(object({
    id                = string
    arn               = string
    vpc_id            = string
    cidr_block        = string
    availability_zone = string
  }))
}

variable "default_log_retention_days" {
  description = "Retention applied to any subnet's flow log group not named in log_retention_days"
  type        = number
  default     = 14
}

variable "log_retention_days" {
  description = "Per-subnet retention override, keyed by the same subnet names as var.subnets (e.g. keep mgmt_subnet longer for audit, expire noisy data subnets sooner)"
  type        = map(number)
  default     = {}
}
