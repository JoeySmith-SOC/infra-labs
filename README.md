# infra-labs

Terminal-first infrastructure lab for IAM, automation, and homelab projects.

## Contents
- **Ansible** for provisioning/orchestration
- **Chef** for configuration/state enforcement
- **VM templates** and helper scripts
- **Docs** and lab write-ups

## Quick start
```bash
# activate venv
source .venv/bin/activate
# run a connectivity test (once hosts are defined)
ansible -i ansible/inventories/hosts.ini all -m ping

