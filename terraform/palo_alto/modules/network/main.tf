resource "aws_vpc" "security_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Security-VPC"
  }
}

resource "aws_subnet" "pa-data-subnet" {
  vpc_id            = aws_vpc.security_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "PA-Data-subnet"
  }
}

resource "aws_subnet" "pa-mgmt-subnet" {
  vpc_id            = aws_vpc.security_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "PA-Mgmt-Subnet"
  }
}

resource "aws_subnet" "gwlb-subnet" {
  vpc_id            = aws_vpc.security_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "GWLB-Subnet"
  }
}

# Public subnet for the bastion host - the only thing in security_vpc that's
# internet-reachable. Mgmt/data/gwlb subnets stay fully private.
resource "aws_internet_gateway" "security_vpc" {
  vpc_id = aws_vpc.security_vpc.id

  tags = {
    Name = "Security-VPC-IGW"
  }
}

resource "aws_subnet" "bastion-subnet" {
  vpc_id            = aws_vpc.security_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Bastion-Subnet"
  }
}

resource "aws_route_table" "bastion" {
  vpc_id = aws_vpc.security_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.security_vpc.id
  }

  tags = {
    Name = "Bastion-RT"
  }
}

resource "aws_route_table_association" "bastion" {
  subnet_id      = aws_subnet.bastion-subnet.id
  route_table_id = aws_route_table.bastion.id
}


resource "aws_vpc" "customer_vpc" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "Consumer-VPC"
  }
}

resource "aws_subnet" "application_subnet" {
  vpc_id            = aws_vpc.customer_vpc.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "us-east-1b"


  tags = {
    Name = "Application-Subnet"
  }
}

# Dedicated subnet for the GWLB endpoint. The endpoint cannot live in the
# same subnet as the workloads it inspects - a subnet's traffic can't be
# routed to an endpoint inside that subnet.
resource "aws_subnet" "gwlbe-subnet" {
  vpc_id            = aws_vpc.customer_vpc.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "GWLBe-Subnet"
  }
}

# Distributed egress: inspected traffic hairpins back from the GWLBe into
# this VPC and exits through this IGW. Keeps the firewall a clean two-NIC
# GWLB appliance and avoids needing peering or a transit gateway.
resource "aws_internet_gateway" "customer_vpc" {
  vpc_id = aws_vpc.customer_vpc.id

  tags = {
    Name = "Consumer-VPC-IGW"
  }
}

# Minimal test workload behind the GWLB endpoint, to generate/receive
# traffic that gets routed out through the firewall for inspection (see the
# application_subnet route table below). Same key material as the other
# instances (var.ssh_public_key_path), registered as its own aws_key_pair since this
# is a separate Terraform state from pa_fw_deploy.
resource "aws_key_pair" "app_instance" {
  key_name   = "network-app-instance-key"
  public_key = local.ssh_public_key
}

data "aws_ami" "app_instance" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "app_instance" {
  name        = "app-instance-sg"
  description = "Minimal test instance in the application subnet"
  vpc_id      = aws_vpc.customer_vpc.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "app-instance-sg"
  }
}

# Public IP so the IGW has an address to 1:1 NAT for this instance. A NAT
# gateway would also work but is an extra resource with no benefit here.
resource "aws_instance" "app_instance" {
  ami                         = data.aws_ami.app_instance.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.application_subnet.id
  vpc_security_group_ids      = [aws_security_group.app_instance.id]
  key_name                    = aws_key_pair.app_instance.key_name
  associate_public_ip_address = true

  tags = {
    Name = "app-instance"
  }
}

resource "aws_lb" "pa_gwlb" {
  name               = "pa-gwlb"
  internal           = false
  load_balancer_type = "gateway"
  #   security_groups    = [aws_security_group.lb_sg.id]
  subnets = [aws_subnet.gwlb-subnet.id]

  enable_deletion_protection = false

  tags = {
    Environment = "Test"
  }
}

# Looked up by tag rather than a terragrunt dependency output, because the
# firewall's ENI lives in the pa_fw_deploy state and pa_fw_deploy already
# depends on this module's subnet outputs - a dependency back from network
# to pa_fw_deploy would be a cycle. Tag is set on the ENI in
# modules/pa_fw_deploy/main.tf (aws_network_interface.gwlb_data).
#
# Uses the plural data source (returns a possibly-empty list) rather than
# the singular one (errors if zero match), since network deploys before
# pa_fw_deploy and the ENI won't exist yet on a first apply here.
data "aws_network_interfaces" "pa_fw_data" {
  filter {
    name   = "tag:Name"
    values = ["pa-fw-gwlb-data-eni"]
  }
}

# Only fetches interface details (private_ip, etc.) once the plural lookup
# above actually found the ENI - keeps this from erroring pre-pa_fw_deploy.
data "aws_network_interface" "pa_fw_data" {
  count = length(data.aws_network_interfaces.pa_fw_data.ids) > 0 ? 1 : 0
  id    = tolist(data.aws_network_interfaces.pa_fw_data.ids)[0]
}

resource "aws_lb_target_group" "pa_gwlb_tg" {
  name        = "pa-gwlb-tg"
  target_type = "ip" # not "instance" - that would target the primary (mgmt) ENI, not the data one
  vpc_id      = aws_vpc.security_vpc.id
  port        = 6081
  protocol    = "GENEVE"

  health_check {
    protocol = "TCP"
    port     = 80 # TODO: point this at a port the firewall actually answers health checks on
  }
}

# Skipped entirely until the firewall's data ENI exists (see above). Re-run
# `terragrunt apply` on network after pa_fw_deploy is up to register it.
resource "aws_lb_target_group_attachment" "pa_fw_data" {
  count            = length(data.aws_network_interface.pa_fw_data) > 0 ? 1 : 0
  target_group_arn = aws_lb_target_group.pa_gwlb_tg.arn
  target_id        = data.aws_network_interface.pa_fw_data[0].private_ip
  port             = 6081
}

resource "aws_lb_listener" "pa_gwlb_listener" {
  load_balancer_arn = aws_lb.pa_gwlb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pa_gwlb_tg.arn
  }
}

# 2. Create the GWLB Endpoint Service
resource "aws_vpc_endpoint_service" "gwlb_service" {
  depends_on = [resource.aws_lb.pa_gwlb]

  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.pa_gwlb.arn]
}

# 3. Create the Gateway Load Balancer Endpoint (GWLBe) in the Consumer VPC
resource "aws_vpc_endpoint" "gwlbe" {
  depends_on = [aws_vpc.customer_vpc, aws_lb.pa_gwlb]

  vpc_id            = aws_vpc.customer_vpc.id
  service_name      = aws_vpc_endpoint_service.gwlb_service.service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.gwlbe-subnet.id]

  tags = {
    Name = "gwlb-endpoint"
  }

  # Moving a GWLB endpoint between subnets requires a replacement (AWS only
  # supports removing subnets from Interface endpoints), and it can't be
  # deleted while a route table still targets it. Creating the replacement
  # first lets dependent routes re-point before the old one goes away.
  lifecycle {
    create_before_destroy = true
  }
}

# Sends all non-local traffic from the application subnet through the GWLB
# endpoint for inspection before it continues to its real destination.
resource "aws_route_table" "application_subnet" {
  vpc_id = aws_vpc.customer_vpc.id

  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = aws_vpc_endpoint.gwlbe.id
  }

  tags = {
    Name = "Application-Subnet-RT"
  }
}

resource "aws_route_table_association" "application_subnet" {
  subnet_id      = aws_subnet.application_subnet.id
  route_table_id = aws_route_table.application_subnet.id
}

# Once the GWLBe hands inspected traffic back, it continues out to the
# internet from here.
resource "aws_route_table" "gwlbe_subnet" {
  vpc_id = aws_vpc.customer_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.customer_vpc.id
  }

  tags = {
    Name = "GWLBe-Subnet-RT"
  }
}

resource "aws_route_table_association" "gwlbe_subnet" {
  subnet_id      = aws_subnet.gwlbe-subnet.id
  route_table_id = aws_route_table.gwlbe_subnet.id
}

# Ingress routing (edge association): return traffic arriving at the IGW is
# sent to the GWLBe for inspection instead of straight to the instance.
# Without this the firewall only ever sees one half of each session.
resource "aws_route_table" "customer_igw_edge" {
  vpc_id = aws_vpc.customer_vpc.id

  route {
    cidr_block      = aws_subnet.application_subnet.cidr_block
    vpc_endpoint_id = aws_vpc_endpoint.gwlbe.id
  }

  tags = {
    Name = "Consumer-VPC-IGW-Edge-RT"
  }
}

# Associated to the gateway itself rather than a subnet - that is what makes
# this an edge route table.
resource "aws_route_table_association" "customer_igw_edge" {
  gateway_id     = aws_internet_gateway.customer_vpc.id
  route_table_id = aws_route_table.customer_igw_edge.id
}
