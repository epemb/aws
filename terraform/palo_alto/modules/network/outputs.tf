output "subnets" {
  description = "Map of subnet name to its attributes"
  value = {
    for name, subnet in local.subnets : name => {
      id                = subnet.id
      arn               = subnet.arn
      vpc_id            = subnet.vpc_id
      cidr_block        = subnet.cidr_block
      availability_zone = subnet.availability_zone
    }
  }
}
