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
else
    echo "Starting k3s agent, server IP: ${k3s_server_private_ip}"
    until (curl -sfL https://get.k3s.io | K3S_TOKEN="${token}" K3S_URL="https://${k3s_server_private_ip}:6443" sh -s); do
        echo 'k3s did not start, retrying in 2 seconds...'
        sleep 2
    done
fi