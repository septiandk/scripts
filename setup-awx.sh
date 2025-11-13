#!/bin/bash
set -euo pipefail

# Konfigurasi yang bisa diubah
AWX_BRANCH="17.0.1"
AWX_REPO="https://github.com/ansible/awx.git"
INSTALL_DIR="/opt/awx"
ADMIN_USER="admin"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-ChangeMe123!}"
HOST_PORT=80

echo "=== AWX Docker setup script ==="
echo "Branch: ${AWX_BRANCH}"
echo "Install dir: ${INSTALL_DIR}"
echo "Admin user: ${ADMIN_USER}"
echo "Admin password: ${ADMIN_PASSWORD}"
echo "Host port: ${HOST_PORT}"
echo

# 1. Update & upgrade sistem
echo "--- Updating & upgrading system ---"
sudo apt update -y
sudo apt upgrade -y

# 2. Cek apakah Docker sudah terinstal
if ! command -v docker &> /dev/null; then
  echo "--- Docker not found. Installing Docker (official method) ---"

  # Remove old versions
  sudo apt remove -y docker docker-engine docker.io containerd runc || true

  # Add Docker’s official GPG key
  sudo apt install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  # Set up the repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install Docker Engine
  sudo apt update -y
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Enable & start Docker
  sudo systemctl enable docker
  sudo systemctl start docker

  echo "--- Docker installed successfully ---"
else
  echo "--- Docker already installed ---"
fi

# 3. Cek docker-compose (plugin)
if ! docker compose version &>/dev/null; then
  echo "--- Installing docker-compose via pip (fallback) ---"
  sudo apt install -y python3-pip
  sudo pip3 install docker-compose
else
  echo "--- docker compose plugin already available ---"
fi

# 4. Install Ansible & dependensi lainnya
echo "--- Installing Ansible & dependencies ---"
sudo apt install -y python3-setuptools python3-pip git pwgen
sudo pip3 install ansible

echo "--- Verifying installations ---"
ansible --version
docker --version
docker compose version || docker-compose version

# 5. Clone AWX repo
echo "--- Cloning AWX repository ---"
sudo mkdir -p "${INSTALL_DIR}"
sudo chown "$(whoami)":"$(whoami)" "${INSTALL_DIR}"
if [ ! -d "${INSTALL_DIR}/awx" ]; then
  git clone -b "${AWX_BRANCH}" "${AWX_REPO}" "${INSTALL_DIR}/awx"
else
  echo "AWX repo already exists in ${INSTALL_DIR}/awx"
fi

# 6. Prepare installer directory
echo "--- Entering installer directory ---"
cd "${INSTALL_DIR}/awx/installer"

# 7. Generate secret key
echo "--- Generating secret key for AWX ---"
SECRET_KEY=$(pwgen -N 1 -s 30)
echo "Secret key: ${SECRET_KEY}"

# 8. Configure inventory file
INVENTORY_FILE="./inventory"
echo "--- Configuring inventory file ---"
cp inventory inventory.bak || true

sed -i "s/^admin_user=.*$/admin_user=${ADMIN_USER}/" "${INVENTORY_FILE}"
sed -i "s/^admin_password=.*$/admin_password=${ADMIN_PASSWORD}/" "${INVENTORY_FILE}"
sed -i "s/^#\?secret_key=.*$/secret_key=${SECRET_KEY}/" "${INVENTORY_FILE}"
sed -i "s/^#\?host_port=.*$/host_port=${HOST_PORT}/" "${INVENTORY_FILE}"

echo "Inventory configured with:"
grep -E "admin_user|admin_password|secret_key|host_port" "${INVENTORY_FILE}"
echo

# 9. Deploy AWX
echo "--- Running Ansible playbook to install AWX ---"
ansible-playbook -i "${INVENTORY_FILE}" install.yml

# 10. Verifikasi
echo "--- Checking running containers ---"
sudo docker ps

echo
echo "=== AWX should now be accessible via http://<your-server-ip>:${HOST_PORT} ==="
echo "Login with user: ${ADMIN_USER} and password: ${ADMIN_PASSWORD}"
echo
echo "Script finished."
