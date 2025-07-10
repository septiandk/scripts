#!/bin/bash
set -e

# ===========================
# ========== MAIN ===========
# ===========================
main() {
    echo "[checking] Container runtimes..."

    found_runtime=false

    stop_service_if_running "containerd.service"
    stop_service_if_running "cri-docker.service"
    stop_service_if_running "crio.service"

    if [ "$found_runtime" = false ]; then
        echo "[clean] No active container runtime found."
    fi

    echo "[stopping] kubeadm"
    sudo kubeadm reset -f || echo "[warn] kubeadm reset gave warning"

    echo "[clean] Removing packages if installed..."
    purge_pkg_if_installed kubeadm
    purge_pkg_if_installed kubectl
    purge_pkg_if_installed kubelet
    purge_pkg_if_installed containerd
    purge_pkg_if_installed cri-o
    purge_pkg_if_installed cri-dockerd

    echo "[clean] Autoremove unused dependencies"
    sudo apt autoremove -y

    echo "[clean] Removing Kubernetes-related directories"
    safe_rm_if_not_empty /etc/containerd
    safe_rm_if_not_empty /etc/kubernetes
    safe_rm_if_not_empty /var/lib/etcd
    safe_rm_if_not_empty /etc/cni
    safe_rm_if_not_empty /var/lib/cni
    safe_rm_if_not_empty /var/lib/kubelet
    safe_rm_if_not_empty ~/.kube
    safe_rm_if_not_empty /opt/cni
    safe_rm_if_not_empty /opt/containerd
    safe_rm_if_not_empty /opt/cri-o
    safe_rm_if_not_empty /etc/cni/net.d

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

    if command -v ipvsadm >/dev/null; then
        echo "[clean] Flushing IPVS"
        sudo ipvsadm --clear
    fi

    echo "[done] Kubernetes reset complete."
}

# ===========================
# ===== Helper Functions ====
# ===========================

# Hapus file/direktori hanya jika ada
safe_rm() {
    if [ -e "$1" ]; then
        echo "[clean] Removing: $1"
        sudo rm -rf "$1"
    fi
}

# Hapus direktori hanya jika ada dan tidak kosong
safe_rm_if_not_empty() {
    if [ -d "$1" ] && [ "$(ls -A "$1" 2>/dev/null)" ]; then
        echo "[clean] Removing non-empty dir: $1"
        sudo rm -rf "$1"
    fi
}

# Stop service jika aktif
stop_service_if_running() {
    local svc="$1"
    if systemctl list-units --type=service --no-legend | grep -q "$svc"; then
        echo "[stopping] $svc"
        sudo systemctl stop "$svc"
        found_runtime=true
    fi
}

# Hapus package hanya jika terinstal
purge_pkg_if_installed() {
    local pkg="$1"
    if dpkg -l | grep -q "^ii  $pkg "; then
        echo "[removing] package $pkg"
        sudo apt purge -y "$pkg"
    fi
}

# ===========================
# ========= RUN =============
# ===========================

main
