variable "subnets" {
  description = "Map of subnet name to its attributes, from the network module's outputs"
  type = map(object({
    id                = string
    arn               = string
    vpc_id            = string
    cidr_block        = string
    availability_zone = string
  }))
}

variable "mgmt_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the PA-VM management interface (HTTPS UI + SSH CLI)"
  type        = list(string)
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key registered for instance access. The default is a placeholder - set TF_VAR_ssh_public_key_path in your shell to point at your own key rather than committing a personal path."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
