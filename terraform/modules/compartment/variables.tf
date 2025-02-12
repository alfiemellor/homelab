variable "name" {
  description = "Name of the compartment"
  type        = string
}
variable "description" {
  description = "Description of the compartment"
  type        = string
  default     = ""
}
variable "enable_delete" {
  description = "Whether the compartment can be deleted"
  type        = bool
  default     = true
}
variable "parent_compartment_id" {
  description = "Parent compartment OCID"
  type        = string
}
variable "freeform_tags" {
  description = "Freeform tags for the compartment"
  type        = map(string)
  default     = {}
}
variable "defined_tags" {
  description = "Defined tags for the compartment"
  type        = map(string)
  default     = {}
}