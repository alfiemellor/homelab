resource "oci_core_vcn" "vcn" {
  cidr_block     = var.cidr_block
  compartment_id = var.compartment_id
  display_name   = var.vcn_name
  dns_label      = var.dns_label
}

resource "oci_core_subnet" "subnet" {
  cidr_block                 = var.subnet_cidr_block
  compartment_id             = var.compartment_id
  display_name               = var.subnet_name
  dns_label                  = var.subnet_dns_label
  vcn_id                     = oci_core_vcn.vcn.id
  security_list_ids          = [oci_core_vcn.vcn.default_security_list_id]
  route_table_id             = oci_core_route_table.route_table.id
  dhcp_options_id            = oci_core_vcn.vcn.default_dhcp_options_id
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_default_security_list" "default_list" {
  manage_default_resource_id = oci_core_vcn.vcn.default_security_list_id

  display_name = "Outbound and Inbound (default)"

  egress_security_rules {
    protocol    = "all"
    description = "Allow outbound traffic"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol    = "all"
    description = "Allow inbound traffic from subnets"
    source      = "10.0.0.0/16"
  }

  # Nothing else is reachable from the internet: SSH, kubectl and apps are
  # reached over Tailscale. This only lets peers make direct WireGuard
  # connections instead of falling back to a DERP relay.
  ingress_security_rules {
    protocol    = "17"
    description = "Allow Tailscale direct connections"
    udp_options {
      min = 41641
      max = 41641
    }
    source = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol    = "1"
    description = "Allow path MTU discovery"
    icmp_options {
      type = 3
      code = 4
    }
    source = "0.0.0.0/0"
  }
}

resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = var.internet_gateway_name
}

resource "oci_core_route_table" "route_table" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = var.route_table_name

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet_gateway.id
  }
}