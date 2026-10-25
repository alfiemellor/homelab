#!/bin/bash

iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X

netfilter-persistent save

# Join the tailnet before anything else. The security list only allows
# Tailscale in from the internet, so this is the only way to reach the node.
curl -fsSL https://tailscale.com/install.sh | sh
until tailscale up --auth-key="${tailscale_auth_key}" --hostname="$HOSTNAME" --advertise-tags=tag:oci; do
    echo 'tailscale did not come up, retrying in 5 seconds...'
    sleep 5
done
TAILSCALE_IP=$(tailscale ip -4)
TAILSCALE_FQDN=$(tailscale status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')

if [[ "$HOSTNAME" =~ "oci-k3s-server" ]]; then
    SERVER_PRIVATE_IP=$(hostname -I | awk '{print $1}')
    echo "Starting k3s server, node IP: $SERVER_PRIVATE_IP, tailnet IP: $TAILSCALE_IP"
    curl -sfL https://get.k3s.io | K3S_TOKEN="${token}" sh -s - server --node-ip=$SERVER_PRIVATE_IP --tls-san=$SERVER_PRIVATE_IP --tls-san=$TAILSCALE_IP --tls-san=$HOSTNAME --tls-san=$TAILSCALE_FQDN --cluster-init --disable traefik --disable servicelb

    # Wait for Kubernetes API to be available
    while ! kubectl get nodes; do sleep 5; done

    # Identity for the home cluster's ArgoCD to manage this cluster with, the
    # same objects `argocd cluster add` would create
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF
else
    echo "Starting k3s agent, server IP: ${k3s_server_private_ip}"
    until (curl -sfL https://get.k3s.io | K3S_TOKEN="${token}" K3S_URL="https://${k3s_server_private_ip}:6443" sh -s); do
        echo 'k3s did not start, retrying in 2 seconds...'
        sleep 2
    done
fi
