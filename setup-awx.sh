#!/bin/bash
set -euo pipefail

# Konfigurasi yang bisa diubah
AWX_BRANCH="17.1.0"
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

# 3.5. Pastikan Python3 tersedia
echo "--- Ensuring Python3 is installed ---"
if ! command -v python3 &> /dev/null; then
  sudo apt install -y python3 python3-venv python3-distutils
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

# 6.5. Patch compose.yml untuk pakai docker compose plugin (bukan docker-compose)
echo "--- Patching compose.yml to use docker compose ---"
cat > /opt/awx/awx/installer/roles/local_docker/tasks/compose.yml <<'EOF'
---
- name: Create {{ docker_compose_dir }} directory
  file:
    path: "{{ docker_compose_dir }}"
    state: directory

- name: Create Redis socket directory
  file:
    path: "{{ docker_compose_dir }}/redis_socket"
    state: directory
    mode: 0777

- name: Create Docker Compose Configuration
  template:
    src: "{{ item.file }}.j2"
    dest: "{{ docker_compose_dir }}/{{ item.file }}"
    mode: "{{ item.mode }}"
  loop:
    - file: environment.sh
      mode: "0600"
    - file: credentials.py
      mode: "0600"
    - file: docker-compose.yml
      mode: "0600"
    - file: nginx.conf
      mode: "0600"
    - file: redis.conf
      mode: "0664"
  register: awx_compose_config

- name: Render SECRET_KEY file
  copy:
    content: "{{ secret_key }}"
    dest: "{{ docker_compose_dir }}/SECRET_KEY"
    mode: 0600
  register: awx_secret_key

- block:
    - name: Remove AWX containers before migrating postgres so that the old postgres container does not get used
      shell: docker compose down
      changed_when: false
      args:
        chdir: "{{ docker_compose_dir }}"
      ignore_errors: true

    - name: Run migrations in task container
      shell: docker compose run --rm task awx-manage migrate --no-input
      changed_when: false
      args:
        chdir: "{{ docker_compose_dir }}"

    - name: Start the containers
      shell: docker compose up -d
      changed_when: false
      args:
        chdir: "{{ docker_compose_dir }}"
      when: awx_compose_config is changed or awx_secret_key is changed
      register: awx_compose_start

    - name: Update CA trust in awx_web container
      command: docker exec awx_web '/usr/bin/update-ca-trust'
      when: awx_compose_config.changed or awx_compose_start.changed

    - name: Update CA trust in awx_task container
      command: docker exec awx_task '/usr/bin/update-ca-trust'
      when: awx_compose_config.changed or awx_compose_start.changed

    - name: Wait for launch script to create user
      wait_for:
        timeout: 10
      delegate_to: localhost

    - name: Create Preload data
      command: docker exec awx_task bash -c "/usr/bin/awx-manage create_preload_data"
      when: create_preload_data|bool
      register: cdo
      changed_when: "'added' in cdo.stdout"
  when: compose_start_containers|bool
EOF
echo "--- compose.yml patched successfully ---"

sudo sed -i 's|{{ *docker_compose_dir *}}|/root/.awx/awxcompose|g' /opt/awx/awx/installer/roles/local_docker/templates/docker-compose.yml.j2

# 7. Generate secret key
echo "--- Generating secret key for AWX ---"
SECRET_KEY=$(pwgen -N 1 -s 30)
echo "Secret key: ${SECRET_KEY}"

# 8. Configure inventory file
INVENTORY_FILE="./inventory"
echo "--- Configuring inventory file ---"
cp inventory inventory.bak || true

# Ganti baris dengan toleransi spasi
sed -i -E "s|^#?\s*admin_user\s*=.*|admin_user=${ADMIN_USER}|" "${INVENTORY_FILE}"
sed -i -E "s|^#?\s*admin_password\s*=.*|admin_password=${ADMIN_PASSWORD}|" "${INVENTORY_FILE}"
sed -i -E "s|^#?\s*secret_key\s*=.*|secret_key=${SECRET_KEY}|" "${INVENTORY_FILE}"
sed -i -E "s|^#?\s*host_port\s*=.*|host_port=${HOST_PORT}|" "${INVENTORY_FILE}"

echo "Inventory configured with:"
grep -E "admin_user|admin_password|secret_key|host_port" "${INVENTORY_FILE}" | sed 's/^/  /'
echo

if ! grep -q "^admin_password=" "${INVENTORY_FILE}"; then
  echo "ERROR: admin_password tidak ter-set dengan benar di ${INVENTORY_FILE}"
  exit 1
fi

# 9. Deploy AWX
echo "--- Running Ansible playbook to install AWX ---"
alias docker-compose='docker compose'

ansible-playbook -i "${INVENTORY_FILE}" install.yml -e "ansible_python_interpreter=/usr/bin/python3"

# 10. Verifikasi
echo "--- Checking running containers ---"
sudo docker ps

echo
echo "=== AWX should now be accessible via http://<your-server-ip>:${HOST_PORT} ==="
echo "Login with user: ${ADMIN_USER} and password: ${ADMIN_PASSWORD}"
echo
echo "Script finished."
