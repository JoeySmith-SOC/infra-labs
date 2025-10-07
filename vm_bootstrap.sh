#!/usr/bin/env bash
set -euo pipefail

# === VM defaults (override via env) ===
VM_NAME="${VM_NAME:-ubuntu-lab01}"
VM_RAM_MB="${VM_RAM_MB:-2048}"
VM_VCPUS="${VM_VCPUS:-2}"
VM_DISK_GB="${VM_DISK_GB:-16}"
CI_USER="${CI_USER:-lab}"
# Public key used to log into the new VM:
# - If running on laptop (SSH path), this is on the laptop
# - If running on Aurelius (LOCAL path), set to a key that exists on Aurelius
PUBKEY_PATH_DEFAULT="$HOME/.ssh/id_ed25519_lab.pub"
[[ -f "$PUBKEY_PATH_DEFAULT" ]] || PUBKEY_PATH_DEFAULT="$HOME/.ssh/id_ed25519.pub"
PUBKEY_PATH="${PUBKEY_PATH:-$PUBKEY_PATH_DEFAULT}"

# === Figure out repo root & venv ===
cd "$(git rev-parse --show-toplevel 2>/dev/null || dirname "$0")"
if [[ ! -d .venv ]]; then python3 -m venv .venv; fi
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install "ansible>=9.0.0" >/dev/null
ansible-galaxy collection install community.general community.libvirt ansible.posix >/dev/null

# === Decide control mode ===
# If we are actually on Aurelius, use LOCAL inventory; else use SSH inventory
HOSTNAME_NOW="$(hostname -s 2>/dev/null || true)"
if [[ "$HOSTNAME_NOW" == "Aurelius" ]] && [[ -f ansible/inventories/hosts.local.ini ]]; then
  INV="ansible/inventories/hosts.local.ini"
  echo "[i] Detected host 'Aurelius' — using LOCAL inventory: $INV"
else
  INV="ansible/inventories/hosts.ini"
  echo "[i] Using SSH inventory: $INV"
fi

echo "[i] Inventory graph:"
ansible-inventory -i "$INV" --graph || { echo "[✗] inventory not usable"; exit 1; }

echo "[i] Creating VM '$VM_NAME' (RAM ${VM_RAM_MB}MB, vCPUs ${VM_VCPUS}, disk ${VM_DISK_GB}G)..."
ansible-playbook -i "$INV" ansible/playbooks/20_create_vm_ubuntu_cloudimg.yml \
  -e vm_name="$VM_NAME" \
  -e vm_memory_mb="$VM_RAM_MB" \
  -e vm_vcpus="$VM_VCPUS" \
  -e vm_disk_gb="$VM_DISK_GB" \
  -e ci_user="$CI_USER" \
  -e controller_pubkey_path="$PUBKEY_PATH"

echo "[✓] Done. VM '$VM_NAME' built. If an IP was discovered, it's saved at /var/lib/libvirt/images/${VM_NAME}.ip on Aurelius."
