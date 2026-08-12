data "aws_ami" "pa-image" {
  most_recent = true
  owners      = ["aws-marketplace"] # or the specific account ID that owns the AMI

  filter {
    name   = "image-id"
    values = ["ami-01f87fffbac374e7d"] # replace with the exact AMI ID
  }
}


resource "aws_key_pair" "pa_fw" {
  key_name   = "pa-fw-key"
  public_key = local.ssh_public_key
}

# Bastion - the only internet-reachable host in security_vpc. Your laptop
# SSHes here (allowed from mgmt_allowed_cidrs), then tunnels/port-forwards
# from here to the firewall's private mgmt interface.
resource "aws_security_group" "bastion" {
  name        = "pa-fw-bastion-sg"
  description = "SSH access to the bastion host"
  vpc_id      = var.subnets["bastion_subnet"].vpc_id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.mgmt_allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pa-fw-bastion-sg"
  }
}

data "aws_ami" "bastion" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.bastion.id
  instance_type               = "t3.micro"
  subnet_id                   = var.subnets["bastion_subnet"].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.pa_fw.key_name
  associate_public_ip_address = true

  tags = {
    Name = "pa-fw-bastion"
  }
}

# eth0 - management. Primary ENI (device_index 0), private only. Only
# reachable through the bastion above - not exposed on the public internet.
resource "aws_security_group" "mgmt" {
  name        = "pa-fw-mgmt-sg"
  description = "Management access to the PA-VM firewall"
  vpc_id      = var.subnets["mgmt_subnet"].vpc_id

  ingress {
    description     = "HTTPS admin UI, from the bastion only"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "SSH CLI, from the bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pa-fw-mgmt-sg"
  }
}

resource "aws_network_interface" "mgmt" {
  subnet_id       = var.subnets["mgmt_subnet"].id
  security_groups = [aws_security_group.mgmt.id]

  tags = {
    Name = "pa-fw-mgmt-eni"
  }
}

# eth1 - GWLB data interface (device_index 1). Receives GENEVE-encapsulated
# traffic from the Gateway Load Balancer and returns inspected traffic back
# to it on the same interface, so it must accept UDP/6081 from the GWLB and
# have source/dest checking disabled since it forwards traffic not addressed
# to itself.
# Add 80 + 443 from gwlb for health checks
resource "aws_security_group" "gwlb_data" {
  name        = "pa-fw-gwlb-data-sg"
  description = "GENEVE traffic to/from the Gateway Load Balancer"
  vpc_id      = var.subnets["pa_subnet"].vpc_id

  ingress {
    description = "GENEVE from GWLB"
    from_port   = 6081
    to_port     = 6081
    protocol    = "udp"
    cidr_blocks = [var.subnets["gwlb_subnet"].cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "pa-fw-gwlb-data-sg"
  }
}

resource "aws_network_interface" "gwlb_data" {
  subnet_id         = var.subnets["pa_subnet"].id
  security_groups   = [aws_security_group.gwlb_data.id]
  source_dest_check = false

  tags = {
    Name = "pa-fw-gwlb-data-eni"
  }
}

resource "aws_instance" "pa-instance" {
  ami           = data.aws_ami.pa-image.id
  instance_type = "m5.xlarge"
  key_name      = aws_key_pair.pa_fw.key_name

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.mgmt.id
  }

  network_interface {
    device_index         = 1
    network_interface_id = aws_network_interface.gwlb_data.id
  }

  tags = {
    Name = "pa-firewall"
  }
}