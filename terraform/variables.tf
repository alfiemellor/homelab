variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "parent_compartment_id" {}
variable "region" {}
variable "ssh_authorized_key" {}
variable "private_key" {}
variable "tailscale_auth_key" {
  description = "Reusable, pre-approved Tailscale auth key tagged tag:oci, used once by each node to join the tailnet"
  type        = string
  sensitive   = true
}