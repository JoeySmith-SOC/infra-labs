# setup_lab.sh
#!/usr/bin/env bash
set -euo pipefail

# ====== EDIT THESE (or set as env vars) ======
HV_HOSTNAME="${HV_HOSTNAME:-Aurelius}"            # Inventory/host_vars name
HV_IP="${HV_IP:-192.168.0.25}"                    # Parrot desktop IP
HV_USER="${HV_USER:-ingen}"                       # SSH user on Parrot
SSH_KEY_PATH="${SSH_KEY_PATH:-~/.ssh/id_ed25519_lab}"  # Controller key
MODE="${MODE:-ssh}"                               # ssh | local
# =============================================

ROOT="$(pwd)"
LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR"
STAMP=$(date +"%Y%m%d-%H%M%S")
LOG="$LOGDIR/hypervisor-setup-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1

echo "[i] setup_lab.sh starting at $(date)"
echo "[i] Repo root: $ROOT"
echo "[i] Mode: $MODE  Hostname: $HV_HOSTNAME  IP: $HV_IP  User: $HV_USER"

# 1) Scaffold repo layout
mkdir -p ansible/{inventories,host_vars,playbooks}

# 2) Inventory files
if [[ "$MODE" == "ssh" ]]; then
  cat > ansible/inventories/hosts.ini <<EOF
[hypervisors]
$HV_HOSTNAME

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
EOF

  cat > "ansible/host_vars/${HV_HOSTNAME}.yml" <<EOF
ansible_host: $HV_IP
ansible_user: $HV_USER
ansible_ssh_private_key_file: $SSH_KEY_PATH

# Hypervisor prefs (tweak if desired)
hv_set_hostname: true
hv_hostname: "$HV_HOSTNAME"
hv_disable_wifi: true
hv_ether_iface: "enp7s0"
hv_images_dir: "/var/lib/libvirt/images"
hv_enable_ufw: true
hv_ufw_allow_ssh_from_any: true
hv_enable_fail2ban: true
EOF
else
  # local mode: no SSH connection — run on the desktop itself
  cat > ansible/inventories/hosts.local.ini <<EOF
[hypervisors]
$HV_HOSTNAME ansible_connection=local ansible_python_interpreter=/usr/bin/python3

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
EOF

  cat > "ansible/host_vars/${HV_HOSTNAME}.yml" <<'EOF'
# LOCAL MODE: do not define SSH connection vars here

# Hypervisor prefs
hv_set_hostname: true
hv_hostname: "Aurelius"
hv_disable_wifi: true
hv_ether_iface: "enp7s0"
hv_images_dir: "/var/lib/libvirt/images"
hv_enable_ufw: true
hv_ufw_allow_ssh_from_any: true
hv_enable_fail2ban: true
EOF
fi

# 3) Hypervisor playbook (libvirt/KVM + hardening)
cat > ansible/playbooks/00_hypervisor_full_setup.yml <<'YAML'
- name: Baseline hypervisor setup on Parrot (KVM/libvirt + hardening)
  hosts: all
  become: true
  gather_facts: true

  vars:
    hv_pkgs:
      - qemu-system-x86
      - qemu-utils
      - libvirt-daemon
      - libvirt-daemon-system
      - libvirt-daemon-driver-qemu
      - libvirt-clients
      - virtinst
      - bridge-utils
      - cloud-image-utils
      - qemu-guest-agent
      - openssh-server
      - ufw
      - fail2ban
      - network-manager

  tasks:
    - name: (Optional) set system hostname
      when: hv_set_hostname | default(false)
      hostname:
        name: "{{ hv_hostname }}"

    - name: Ensure /etc/hosts contains the new hostname
      when: hv_set_hostname | default(false)
      lineinfile:
        path: /etc/hosts
        regexp: '^127\.0\.1\.1\s+'
        line: "127.0.1.1   {{ hv_hostname }}"
        create: yes

    - name: Install hypervisor and security packages
      apt:
        name: "{{ hv_pkgs }}"
        state: present
        update_cache: yes

    - name: Ensure NetworkManager is enabled/started
      systemd: { name: NetworkManager, state: started, enabled: true }

    - name: (Optional) disable Wi-Fi radio so Ethernet is primary
      when: hv_disable_wifi | default(false)
      command: nmcli radio wifi off
      changed_when: true

    - name: Enable libvirt sockets (socket-activated)
      systemd: { name: libvirtd.socket, state: started, enabled: true }

    - name: Start virtlogd/virtlockd sockets (ignore if not present)
      systemd: { name: "{{ item }}", state: started, enabled: true }
      loop: [ "virtlogd.socket", "virtlockd.socket" ]
      ignore_errors: true

    - name: Ensure images directory exists
      file: { path: "{{ hv_images_dir }}", state: directory, mode: '0755' }

    - name: Add current user to libvirt + kvm groups (if connected via SSH)
      when: ansible_connection != 'local'
      user: { name: "{{ ansible_user }}", groups: "libvirt,kvm", append: true }

    - name: Add local console user to libvirt + kvm (local mode)
      when: ansible_connection == 'local'
      user: { name: "{{ lookup('env','USER') }}", groups: "libvirt,kvm", append: true }

    - name: Verify libvirt connection
      command: virsh -c qemu:///system list --all
      register: virsh_conn
      changed_when: false

    - name: Check if default network exists
      command: virsh net-info default
      register: netinfo
      failed_when: false
      changed_when: false

    - name: Define default network if missing
      when: "'not found' in (netinfo.stderr | default(''))"
      copy:
        dest: /tmp/default-net.xml
        content: |
          <network>
            <name>default</name>
            <bridge name='virbr0' stp='on' delay='0'/>
            <forward mode='nat'/>
            <ip address='192.168.122.1' netmask='255.255.255.0'>
              <dhcp>
                <range start='192.168.122.100' end='192.168.122.254'/>
              </dhcp>
            </ip>
          </network>

    - name: Create default network from XML (if needed)
      when: "'not found' in (netinfo.stderr | default(''))"
      command: virsh net-define /tmp/default-net.xml

    - name: Autostart and start default network
      shell: |
        set -e
        virsh net-autostart default
        virsh net-start default 2>/dev/null || true
      args: { executable: /bin/bash }

    - name: Enable and start qemu-guest-agent service
      systemd: { name: qemu-guest-agent, state: started, enabled: true }
      ignore_errors: true

    - name: (Optional) Enable UFW
      when: hv_enable_ufw | default(true)
      command: ufw --force enable
      register: ufw_enable
      changed_when: "'active' in ufw_enable.stdout.lower() or 'enabling' in ufw_enable.stdout.lower()"

    - name: Allow SSH in UFW
      when: hv_enable_ufw | default(true)
      command: ufw allow OpenSSH
      changed_when: true

    - name: (Optional) install minimal Fail2ban jail.local for sshd
      when: hv_enable_fail2ban | default(true)
      copy:
        dest: /etc/fail2ban/jail.d/10-sshd.local
        mode: '0644'
        content: |
          [sshd]
          enabled = true
          bantime = 1h
          findtime = 10m
          maxretry = 5

    - name: Ensure fail2ban is enabled/started
      when: hv_enable_fail2ban | default(true)
      systemd: { name: fail2ban, state: started, enabled: true }

    - name: Final verification (report)
      shell: |
        set -e
        echo "=== libvirt connection ==="
        virsh -c qemu:///system list --all || true
        echo "=== networks ==="
        virsh net-list --all || true
        echo "=== UFW status ==="
        ufw status verbose || true
      args: { executable: /bin/bash }
      register: final_report
      changed_when: false

    - name: Show final summary
      debug: { msg: "{{ final_report.stdout.split('\n') }}" }
YAML

# 4) Python venv + Ansible + collections
if [[ ! -d .venv ]]; then
  echo "[i] Creating venv..."
  python3 -m venv .venv
fi
source .venv/bin/activate
echo "[i] Upgrading pip..."
pip install --upgrade pip
echo "[i] Installing Ansible..."
pip install "ansible>=9.0.0"
echo "[i] Installing collections..."
ansible-galaxy collection install community.general community.libvirt ansible.posix

# 5) Inventory graph + connectivity + run
if [[ "$MODE" == "ssh" ]]; then
  INV="ansible/inventories/hosts.ini"
else
  INV="ansible/inventories/hosts.local.ini"
fi

echo "[i] Inventory graph:"
ansible-inventory -i "$INV" --graph

echo "[i] Connectivity test..."
ansible -i "$INV" "$HV_HOSTNAME" -m ping -vvv || true  # local mode may show 'pong' with different host facts

echo "[i] Running hypervisor setup (sudo prompt expected)..."
ansible-playbook -i "$INV" ansible/playbooks/00_hypervisor_full_setup.yml -K -vv

echo "[✓] Done at $(date). Log: $LOG"
