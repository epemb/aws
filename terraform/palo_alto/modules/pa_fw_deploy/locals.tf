locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
}
