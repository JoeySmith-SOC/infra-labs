#!/usr/bin/env bash
# ================================================================
#  Infra-Labs Phase 1 Finalization Script
#  Target: Parrot (Aurelius) Hypervisor
#  Purpose: finalize baseline, harden host, prep for IAM phase
# ================================================================
set -euo pipefail
LOG="/var/log/infra-finalize.log"
exec > >(tee -a "$LOG") 2>&1

echo "===== Infra-Labs Phase 1 Finalization ====="
date
echo

# ---------- 1. Variables ----------
HOSTNAME="Aurelius"
STATIC_IP="192.168.0.25"
NETMASK="255.255.255.0"
GATEWAY="192.168.0.1"
DNS="1.1.1.1"
ETHER_IFACE=$(ip -br link | awk '/UP/ && !/lo/ {print $1; exit}')

echo "[i] Hostname: $HOSTNAME"
echo "[i] Interface: $ETHER_IFACE"
echo "[i] Static IP: $STATIC_IP"

# ---------- 2. System Update ----------
echo "[+] Updating packages..."
sudo apt update -y
sudo apt full-upgrade -y
sudo apt autoremove -y

# ---------- 3. Ensure core packages ----------
echo "[+] Installing core packages..."
sudo apt install -y qemu-system-x86 qemu-utils libvirt-daemon libvirt-daemon-system \
  libvirt-daemon-driver-qemu libvirt-clients virtinst bridge-utils cloud-image-utils \
  qemu-guest-agent network-manager ufw fail2ban net-tools curl wget vim git unzip

# ---------- 4. Verify libvirt/kvm ----------
echo "[+] Enabling virtualization services..."
sudo systemctl enable --now libvirtd.socket virtlogd.socket virtlockd.socket
sudo usermod -aG libvirt,kvm "$USER"

# ---------- 5. Configure static networking ----------
echo "[+] Configuring static IP..."
NMCONF="/etc/NetworkManager/system-connections/${ETHER_IFACE}.nmconnection"
sudo nmcli con mod "$ETHER_IFACE" ipv4.method manual ipv4.addresses "${STATIC_IP}/24" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS" autoconnect yes
sudo nmcli con down "$ETHER_IFACE" || true
sudo nmcli con up "$ETHER_IFACE"

# ---------- 6. Hostname ----------
echo "[+] Setting hostname..."
sudo hostnamectl set-hostname "$HOSTNAME"
if ! grep -q "$HOSTNAME" /etc/hosts; then
  echo "127.0.1.1   $HOSTNAME" | sudo tee -a /etc/hosts
fi

# ---------- 7. UFW firewall ----------
echo "[+] Configuring UFW..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw --force enable
sudo ufw status verbose

# ---------- 8. Fail2ban hardening ----------
echo "[+] Configuring Fail2ban..."
sudo systemctl enable --now fail2ban
sudo mkdir -p /etc/fail2ban/jail.d
sudo tee /etc/fail2ban/jail.d/10-sshd.local > /dev/null <<'EOF'
[sshd]
enabled = true
port    = ssh
logpath = /var/log/auth.log
bantime = 1h
findtime = 10m
maxretry = 5
EOF
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd || true

# ---------- 9. SSH settings ----------
echo "[+] Hardening SSH..."
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# ---------- 10. Create working directories ----------
echo "[+] Creating lab directories..."
sudo mkdir -p /opt/lab/{isos,images,configs,snapshots,logs}
sudo chown -R "$USER":"$USER" /opt/lab
echo "export LAB_HOME=/opt/lab" | sudo tee /etc/profile.d/lab_home.sh

# ---------- 11. Verify KVM connection ----------
echo "[+] Verifying KVM/libvirt..."
sudo virsh -c qemu:///system list --all || true
sudo virsh net-list --all || true

# ---------- 12. Snapshot baseline ----------
echo "[+] Creating baseline marker..."
sudo tee /opt/lab/snapshots/baseline-info.txt > /dev/null <<EOF
Infra-Labs baseline completed on $(date)
Hostname: $HOSTNAME
Interface: $ETHER_IFACE
IP: $STATIC_IP
EOF

# ---------- 13. System health summary ----------
echo
echo "===== Health Summary ====="
echo "[+] Uptime:" $(uptime -p)
echo "[+] IP address:" $(hostname -I)
echo "[+] UFW:" $(sudo ufw status | head -n 1)
echo "[+] Fail2ban:" $(systemctl is-active fail2ban)
echo "[+] KVM status:" $(sudo virsh list --all | wc -l) "domains listed"
echo
echo "[✓] Phase 1 finalization complete."
echo "Full log: $LOG"
