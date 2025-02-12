resource "oci_identity_compartment" "compartment" {
  name           = var.name
  description    = var.description
  enable_delete  = var.enable_delete
  compartment_id = var.parent_compartment_id
  freeform_tags  = var.freeform_tags
  defined_tags   = var.defined_tags
}