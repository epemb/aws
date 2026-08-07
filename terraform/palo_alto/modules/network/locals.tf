locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))

  subnets = {
    pa_subnet          = aws_subnet.pa-data-subnet
    mgmt_subnet        = aws_subnet.pa-mgmt-subnet
    gwlb_subnet        = aws_subnet.gwlb-subnet
    bastion_subnet     = aws_subnet.bastion-subnet
    application_subnet = aws_subnet.application_subnet
    gwlbe_subnet       = aws_subnet.gwlbe-subnet
  }
}