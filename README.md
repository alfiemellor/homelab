# Homelab

This is for my Homelab, I have a k3s cluster at home running the following hardware:
- ThinkCentre M910q (i5-7500T, 16GB RAM)
- 4x Raspberry Pi 4b (4GB RAM)

Plus I sometimes spin up a cluster on the Oracle Cloud free tier, which I'm just using for testing. The terraform for this deploys a free tier only k3s cluster onto Oracle Cloud with 1 master server and 3 worker nodes. Once the terraform is applied, it can bootstrap ArgoCD which then installs the rest of my applications. From nothing to fully setup Kubernetes cluster takes just a single `terraform apply` and about 10-20 minutes.

After setting up your Oracle Cloud account you need to define all of the variables laid out in `variables.tf` make sure to setup in your Terraform Cloud Workspace as sensitive variables.

I will add more detail about my setup and what I'm running later.