resource "random_string" "k3s_token" {
  length  = 64
  special = false
}

module "oci_compartment" {
  source                = "./modules/compartment"
  name                  = "production"
  description           = "Production compartment"
  parent_compartment_id = var.parent_compartment_id
  freeform_tags         = { Name = "core-compartment" }
}

module "oci_network" {
  source                = "./modules/network"
  depends_on            = [ module.oci_compartment ]
  compartment_id        = module.oci_compartment.compartment_id
  cidr_block            = "10.0.0.0/16"
  vcn_name              = "core-vcn"
  dns_label             = "corevcn"
  subnet_cidr_block     = "10.0.1.0/24"
  subnet_name           = "core-subnet"
  subnet_dns_label      = "coresubnet"
  internet_gateway_name = "core-igw"
  route_table_name      = "core-rt"
}

module "oci_k3s_server" {
  source                = "./modules/instance"
  depends_on            = [module.oci_network]
  count                 = 1
  availability_domain   = "XINj:UK-LONDON-1-AD-1"
  compartment_id        = module.oci_compartment.compartment_id
  shape                 = "VM.Standard.A1.Flex"
  ocpus                 = 1
  memory_in_gbs         = 6
  display_name          = "oci-k3s-server"
  subnet_id             = module.oci_network.subnet_id
  image_id              = "ocid1.image.oc1.uk-london-1.aaaaaaaaa6i2x65thpjcpl7taflmywa7v4loqdorvb4alcsues3pkoil6g3q"
  ssh_authorized_key    = var.ssh_authorized_key
  cluster_token         = random_string.k3s_token.result
  freeform_tags         = { Name = "oci-k3s-server" }
}

module "oci_k3s_workers" {
  source                = "./modules/instance"
  depends_on            = [module.oci_network, module.oci_k3s_server]
  count                 = 3
  availability_domain   = "XINj:UK-LONDON-1-AD-1"
  compartment_id        = module.oci_compartment.compartment_id
  shape                 = "VM.Standard.A1.Flex"
  ocpus                 = 1
  memory_in_gbs         = 6
  display_name          = "oci-k3s-worker-${count.index + 1}"
  subnet_id             = module.oci_network.subnet_id
  image_id              = "ocid1.image.oc1.uk-london-1.aaaaaaaaa6i2x65thpjcpl7taflmywa7v4loqdorvb4alcsues3pkoil6g3q"
  ssh_authorized_key    = var.ssh_authorized_key
  cluster_token         = random_string.k3s_token.result
  k3s_server_private_ip = module.oci_k3s_server[0].private_ip
  freeform_tags         = { Name = "oci-k3s-worker-${count.index + 1}" }
}