variable "admin_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH into the application-subnet test instance"
  type        = list(string)
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key registered for instance access. The default is a placeholder - set TF_VAR_ssh_public_key_path in your shell to point at your own key rather than committing a personal path."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
