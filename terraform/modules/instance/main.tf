resource "oci_core_instance" "instance" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  shape               = var.shape
  display_name        = var.display_name

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = var.image_id
  }

  shape_config {
    ocpus = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }
  
  metadata = {
    ssh_authorized_keys = var.ssh_authorized_key
    user_data = base64encode(templatefile("${path.module}/templates/user_data.sh",
      {
        token                 = var.cluster_token,
        k3s_server_private_ip = var.k3s_server_private_ip
      }
    ))
  }

  freeform_tags = var.freeform_tags
}