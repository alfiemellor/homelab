variable "availability_domain" {}
variable "compartment_id" {}
variable "shape" {}
variable "ocpus" {}
variable "memory_in_gbs" {}
variable "display_name" {}
variable "subnet_id" {}
variable "image_id" {}
variable "ssh_authorized_key" {}
variable "cluster_token" {}
variable "k3s_server_private_ip" {
  description = "The private IP address of the k3s server instance"
  type        = string
  default     = ""
}
variable "bootstrap_argocd" {
  type    = bool
  default = false
}
variable "freeform_tags" {
  type    = map(string)
  default = {}
}