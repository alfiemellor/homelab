#!/bin/bash

iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X

netfilter-persistent save

if [[ "$HOSTNAME" =~ "oci-k3s-server" ]]; then
    SERVER_PUBLIC_IP=$(curl -s ifconfig.io)
    SERVER_PRIVATE_IP=$(hostname -I | awk '{print $1}')
    echo "Starting k3s server, node IP: $SERVER_PRIVATE_IP, and external IP: $SERVER_PUBLIC_IP"
    curl -sfL https://get.k3s.io | K3S_TOKEN="${token}" sh -s - server --node-ip=$SERVER_PRIVATE_IP --node-external-ip=$SERVER_PUBLIC_IP --tls-san=$SERVER_PRIVATE_IP --tls-san=$SERVER_PUBLIC_IP --cluster-init --disable traefik
    
    # Wait for Kubernetes API to be available
    while ! kubectl get nodes; do sleep 5; done

    # Define the total number of nodes in the cluster (master + worker nodes)
    EXPECTED_NODES=4  # TODO: Pull this number as a var from Terraform based on the number of installed nodes
    READY_NODES=0

    while [ $READY_NODES -lt $EXPECTED_NODES ]; do
        READY_NODES=$(kubectl get nodes --no-headers | grep -c 'Ready')
        echo "Waiting for nodes to be ready... ($READY_NODES/$EXPECTED_NODES)"
        sleep 5
    done

    # Install ArgoCD
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # Patch ArgoCD config map to allow Kustomize to build Helm charts
    kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"kustomize.buildOptions":"--enable-alpha-plugins --enable-helm"}}'

    while [[ $(kubectl get pods -n argocd --field-selector=status.phase!=Running | wc -l) -gt 1 ]]; do
        echo "Waiting for ArgoCD to be fully ready..."
        sleep 10
    done

    # Bootstrap ArgoCD applications
    kubectl apply -f https://raw.githubusercontent.com/alfiemellor/homelab/main/apps/argocd/bootstrap.yaml    
else
    echo "Starting k3s agent, server IP: ${k3s_server_private_ip}"
    until (curl -sfL https://get.k3s.io | K3S_TOKEN="${token}" K3S_URL="https://${k3s_server_private_ip}:6443" sh -s); do
        echo 'k3s did not start, retrying in 2 seconds...'
        sleep 2
    done
fi