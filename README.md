# Homelab

This is for my Homelab, which at the moment just lives in the Oracle Cloud free tier, I will likely add a local k3s cluster based on Raspberry Pi's soon as I already have the hardware along with other things as I see fit.

Feel free to copy and use yourself or as inspiration.

For now it deploys a free tier only k3s cluster onto Oracle Cloud with 1 master server and 3 worker nodes.

After setting up your Oracle Cloud account you need to define all of the variables in `variables.tf` in your Terraform Cloud Workspace as sensitive variables, I guess it is OK to leave `region` and even your `ssh_authorized_key` as regular variables.

There is much more to come here such as deploying my apps with ArgoCD and more.