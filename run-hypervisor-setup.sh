#!/usr/bin/env bash
set -euo pipefail
cd ~/Projects/infra-labs

# venv + deps
if [[ ! -d .venv ]]; then python3 -m venv .venv; fi
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install "ansible>=9.0.0" >/dev/null
ansible-galaxy collection install community.general community.libvirt ansible.posix >/dev/null

# sanity + apply
ansible-inventory -i ansible/inventories/hosts.ini --graph
ansible -i ansible/inventories/hosts.ini Aurelius -m ping
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/00_hypervisor_full_setup.yml -K
echo "[✓] Hypervisor setup complete."
