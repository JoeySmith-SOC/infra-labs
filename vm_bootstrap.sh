#!/usr/bin/env bash
set -euo pipefail

# ==== Adjust these for your VM ====
VM_NAME="${VM_NAME:-ubuntu-lab01}"
VM_RAM_MB="${VM_RAM_MB:-2048}"
VM_VCPUS="${VM_VCPUS:-2}"
VM_DISK_GB="${VM_DISK_GB:-16}"
CI_USER="${CI_USER:-lab}"
PUBKEY_PATH="${PUBKEY_PATH:-~/.ssh/id_ed25519_lab.pub}"   # on the CONTROL NODE
# ==================================

cd "$(dirname "$0")"

# Ensure venv + Ansible present
if [[ ! -d .venv ]]; then python3 -m venv .venv; fi
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install "ansible>=9.0.0" >/dev/null
ansible-galaxy collection install community.general community.libvirt ansible.posix >/dev/null

echo "[i] Inventory graph:"
ansible-inventory -i ansible/inventories/hosts.ini --graph

echo "[i] Creating VM '$VM_NAME'..."
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/20_create_vm_ubuntu_cloudimg.yml \
  -e vm_name="$VM_NAME" \
  -e vm_memory_mb="$VM_RAM_MB" \
  -e vm_vcpus="$VM_VCPUS" \
  -e vm_disk_gb="$VM_DISK_GB" \
  -e ci_user="$CI_USER" \
  -e controller_pubkey_path="$PUBKEY_PATH"

echo "[✓] Done. If an IP was discovered, it was saved on Aurelius at /var/lib/libvirt/images/${VM_NAME}.ip"
