variable "compartment_id" {
  type        = string
  description = "OCI tenancy/compartment OCID."
}

variable "region" {
  type    = string
  default = "us-ashburn-1"
}

variable "ssh_public_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO7ZCS39YKZ+E/U0aFXe6qfBTfPOgT6NWN7LoOddv7/0"
}

variable "display_name" {
  type    = string
  default = "personal-oci-vm"
}
