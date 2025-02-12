output "k3s_server_public_ip" {
  description = "The public IP address of the k3s server instance"
  value       = module.oci_k3s_server[*].public_ip
}

output "k3s_worker_public_ips" {
  description = "The public IP address of the k3s worker instance(s)"
  value       = module.oci_k3s_workers[*].public_ip
}

output "cluster_token" {
  description = "value"
  value       = random_string.k3s_token.result
}