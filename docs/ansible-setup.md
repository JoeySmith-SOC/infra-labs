# Ansible setup (control node)

## Create/activate venv
python3 -m venv .venv
source .venv/bin/activate

## Install Ansible + common collections
pip install --upgrade pip
pip install "ansible>=9.0.0"
ansible-galaxy collection install community.general community.libvirt ansible.posix ansible.windows
