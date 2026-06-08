module "vm" {
  source = "git::https://github.com/alexjmiller5/nixos-ocp-tailscale-vm-iac.git//terraform/oci-vm?ref=main"

  compartment_id      = var.compartment_id
  region              = var.region
  vcn_cidr            = "10.0.0.0/16"
  subnet_cidr         = "10.0.0.0/24"
  ocpus               = 1
  memory_gb           = 6
  boot_volume_size_gb = 50
  display_name        = var.display_name
  ssh_public_key      = var.ssh_public_key
}
