#!/bin/bash

set -e

echo "[checking] Container runtimes..."

found_runtime=false

# Cek containerd
if systemctl is-active --quiet containerd; then
    echo "[stopping] containerd"
    sudo systemctl stop containerd
    found_runtime=true
fi

# Cek cri-dockerd
if systemctl list-units --type=service | grep -q cri-docker; then
    echo "[stopping] cri-docker"
    sudo systemctl stop cri-docker
    found_runtime=true
fi

# Cek crio
if systemctl is-active --quiet crio; then
    echo "[stopping] crio"
    sudo systemctl stop crio
    found_runtime=true
fi

if [ "$found_runtime" = false ]; then
    echo "[clean] No active container runtime found."
fi

echo "[stopping] kubeadm"
sudo kubeadm reset -f

echo "[clean] Removing Kubernetes packages"
sudo apt purge -y kubeadm kubectl kubelet containerd cri-o cri-dockerd
sudo apt autoremove -y

echo "[clean] Removing Kubernetes-related directories"
sudo rm -rf /etc/containerd /etc/kubernetes /var/lib/etcd
sudo rm -rf /etc/cni /var/lib/cni /var/lib/kubelet/*
sudo rm -rf ~/.kube /opt/cni /opt/containerd /opt/cri-o

echo "[stopping] Killing Kubernetes-related ports"
for port in 10250 10257 10259 2379 2380 6443; do
    sudo fuser -k ${port}/tcp || true
done

echo "[clean] Removing CNI interfaces"
sudo ip link set cni0 down 2>/dev/null || true
sudo ip link set flannel.1 down 2>/dev/null || true
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true

echo "[clean] Flushing iptables"
sudo iptables -F && sudo iptables -X
sudo iptables -t nat -F && sudo iptables -t nat -X
sudo iptables -t raw -F && sudo iptables -t raw -X
sudo iptables -t mangle -F && sudo iptables -t mangle -X

echo "[done] Kubernetes reset complete."
