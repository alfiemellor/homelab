# Homelab

This is for my Homelab, I have a k3s cluster at home running the following hardware:
- ThinkCentre M910q (i5-7500T, 16GB RAM)
- 4x Raspberry Pi 4b (4GB RAM)

Plus I sometimes spin up a cluster on Oracle Cloud. The terraform for this deploys a k3s cluster with 1 server and 3 worker nodes (1 OCPU, 6GB RAM and a 50GB boot volume each). Nothing on it is exposed to the internet: each node joins my tailnet on boot, and the ArgoCD in my home cluster manages it over Tailscale.

After setting up your Oracle Cloud account you need to define all of the variables laid out in `variables.tf` make sure to setup in your Terraform Cloud Workspace as sensitive variables.

I will add more detail about my setup and what I'm running later.