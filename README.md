# Homelab

This is for my Homelab. It's the GitOps source of truth for two k3s clusters and
everything that runs on them: ArgoCD watches this repo, so merging to `main` is
how things get deployed.

## Hardware

I have a k3s cluster at home running the following hardware:
- ThinkCentre M910q (i5-7500T, 16GB RAM) as the server node (`k3s-01`)
- 4x Raspberry Pi 4b (4GB RAM) as worker nodes (`k3s-02` to `k3s-05`)

Plus a TrueNAS box that serves media over NFS and holds the backups.

I also run a cluster on Oracle Cloud's free tier. The terraform for this deploys a k3s cluster with 1 server and 1 worker node (2 OCPU, 12GB RAM and a 100GB boot volume each). Nothing on it is exposed to the internet: each node joins my tailnet on boot, and the ArgoCD in my home cluster manages it over Tailscale.

## What's running

**Home cluster**
- **Media:** Plex, Tautulli
- **Downloads:** Sonarr, Radarr, Prowlarr, qBittorrent, qui, scdl
- **Home automation:** Home Assistant, Matter Server
- **Finance:** Actual Budget, plus small sync jobs for Trading 212 and Amex
- **Other apps:** Homarr (dashboard), Trilium (notes), TREK (travel), an FTB Evolution Minecraft server
- **Platform:** ArgoCD, Longhorn, cert-manager, CloudNativePG, 1Password operator, Tailscale operator, Intel GPU device plugin
- **Networking:** MetalLB, ingress-nginx (internal and external), external-dns, Cloudflare DDNS and Cloudflare Tunnel
- **Monitoring:** kube-prometheus-stack (Prometheus and Grafana), Loki, Alloy, an SD card health exporter for the Pis

**Oracle Cloud cluster**
- **Project management:** Windshift, Plane (evaluating both currently)
- **Platform:** Longhorn, cert-manager, CloudNativePG, 1Password operator, Tailscale operator, ingress-nginx, external-dns, Prometheus (shown in the home Grafana)

## How it works

- **Deployment:** ArgoCD runs on the home cluster. Two ApplicationSets create one
  Argo application per folder in `apps/overlays/home/` and `apps/overlays/oci/`.
  The folder name is also the namespace. Everything auto-syncs from `main`.
- **Manifests:** each app lives in `apps/base/` as plain YAML and/or a Helm chart
  rendered through Kustomize. Each cluster's overlay picks which of those it runs.
- **Access:** most apps are only reachable over my tailnet. A few are public,
  either directly through the external ingress or through a Cloudflare Tunnel
  with Cloudflare Access in front. DNS for `mellor.dev` is managed automatically
  and TLS certificates come from Let's Encrypt.
- **Secrets:** nothing secret is in this repo. The 1Password operator syncs items
  from a 1Password vault into Kubernetes Secrets.
- **Storage and backups:** app data lives on Longhorn volumes, which are backed up
  nightly to TrueNAS and from there to Google Drive. Media is mounted from TrueNAS
  over NFS.
- **Nodes:** the home nodes are set up and upgraded with Ansible playbooks; the
  Oracle Cloud nodes are created by Terraform and bootstrap k3s and Tailscale on
  first boot.
- **Updates:** Renovate opens PRs every Monday for new container image and Helm
  chart versions.

## Layout

```
apps/
  argocd/clusters/home.yaml   ApplicationSet for the home cluster
  base/                       Manifests and Helm values for every app
  overlays/home/              What runs on the home cluster, one folder per namespace
  overlays/oci/               What runs on the Oracle Cloud cluster
ansible/                      Node setup, k3s install/upgrade and OS update playbooks
terraform/                    Oracle Cloud network and instances
```

## Setup

**Ansible:** copy `ansible/inventory.example.yaml` to `ansible/inventory.yaml` and
`ansible/ansible.example.cfg` to `ansible/ansible.cfg`, then fill in your node IPs,
user and SSH key. The Oracle Cloud nodes have their own inventory,
`ansible/inventory.oci.yaml`, which you pass with `-i`.

**Terraform:** after setting up your Oracle Cloud account you need to define all of the variables laid out in `variables.tf` make sure to setup in your Terraform Cloud Workspace as sensitive variables.

**Checking a change:** to see what an overlay will deploy before you push, run:

```sh
kustomize build --enable-helm apps/overlays/home/<namespace>
```
