# Homelab

This is for my Homelab, which at the moment just lives in the Oracle Cloud free tier, which I'm just using for testing Kubernetes. I'll eventually be running this on hardware at home once I have sorted out my hardware setup.

For now it deploys a free tier only k3s cluster onto Oracle Cloud with 1 master server and 3 worker nodes. Once the terraform is applied, it deploys ArgoCD which then bootstraps the rest of my applications. From nothing to fully setup Kubernetes cluster takes just a single `terraform apply` and about 10-20 minutes.

After setting up your Oracle Cloud account you need to define all of the variables laid out in `variables.tf` make sure to setup in your Terraform Cloud Workspace as sensitive variables.
