#!/bin/bash
set -e

echo "[checking] Container runtimes..."

# Helper: Hapus file/folder jika ada
safe_rm() {
    [ -e "$1" ] && sudo rm -rf "$1"
}

# Helper: Stop service jika aktif
stop_service_if_running() {
    local svc="$1"
    if systemctl list-units --type=service --no-legend | grep -q "$svc"; then
        echo "[stopping] $svc"
        sudo systemctl stop "$svc"
    fi
}

# Helper: Hapus package jika terinstal
purge_pkg_if_installed() {
    local pkg="$1"
    if dpkg -l | grep -q "^ii  $pkg "; then
        echo "[removing] package $pkg"
        sudo apt purge -y "$pkg"
    fi
}

# Stop runtimes
stop_service_if_running "containerd.service"
stop_service_if_running "cri-docker.service"
stop_service_if_running "crio.service"

# Reset kubeadm
echo "[stopping] kubeadm"
sudo kubeadm reset -f

# Hapus paket Kubernetes & runtimes
echo "[clean] Removing packages if installed..."
purge_pkg_if_installed kubeadm
purge_pkg_if_installed kubectl
purge_pkg_if_installed kubelet
purge_pkg_if_installed containerd
purge_pkg_if_installed cri-o
purge_pkg_if_installed cri-dockerd

echo "[clean] Autoremove unused dependencies"
sudo apt autoremove -y

# Hapus direktori/file
echo "[clean] Removing Kubernetes-related directories"
safe_rm /etc/containerd
safe_rm /etc/kubernetes
safe_rm /var/lib/etcd
safe_rm /etc/cni
safe_rm /var/lib/cni
safe_rm /var/lib/kubelet/*
safe_rm ~/.kube
safe_rm /opt/cni
safe_rm /opt/containerd
safe_rm /opt/cri-o
safe_rm /etc/cni/net.d

# Bunuh port
echo "[stopping] Killing Kubernetes-related ports"
for port in 10250 10257 10259 2379 2380 6443; do
    sudo fuser -k ${port}/tcp || true
done

# Hapus network interface CNI
echo "[clean] Removing CNI interfaces"
sudo ip link set cni0 down 2>/dev/null || true
sudo ip link set flannel.1 down 2>/dev/null || true
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true

# Reset iptables
echo "[clean] Flushing iptables"
sudo iptables -F && sudo iptables -X
sudo iptables -t nat -F && sudo iptables -t nat -X
sudo iptables -t raw -F && sudo iptables -t raw -X
sudo iptables -t mangle -F && sudo iptables -t mangle -X

# Optional: Bersihkan IPVS
if command -v ipvsadm >/dev/null; then
    echo "[clean] Flushing IPVS"
    sudo ipvsadm --clear
fi

echo "[done] Kubernetes reset complete."
