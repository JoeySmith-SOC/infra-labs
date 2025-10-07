#!/usr/bin/env bash
# ================================================================
# Infra-Labs Phase 1 Finalization (v2, auto-detect NM connection)
# Target: Parrot (Aurelius) Hypervisor
# ================================================================
set -euo pipefail

# --------- User-overridable settings (env vars) ----------
HV_HOSTNAME="${HV_HOSTNAME:-Aurelius}"

# IP configuration (default Static). To use DHCP: export IP_METHOD=auto
IP_METHOD="${IP_METHOD:-manual}"          # manual | auto
STATIC_IP="${STATIC_IP:-192.168.0.25}"    # used only if IP_METHOD=manual
NETMASK_BITS="${NETMASK_BITS:-24}"        # CIDR bits (e.g., 24 for 255.255.255.0)
GATEWAY="${GATEWAY:-192.168.0.1}"         # used only if IP_METHOD=manual
DNS_SERVERS="${DNS_SERVERS:-1.1.1.1 8.8.8.8}"

# Optionally disable Wi-Fi radio for stability on a headless hypervisor
DISABLE_WIFI="${DISABLE_WIFI:-true}"      # true | false
# --------------------------------------------------------

LOG="/var/log/infra-finalize-v2.log"
exec > >(tee -a "$LOG") 2>&1

msg()  { printf "\n[+] %s\n" "$*"; }
warn() { printf "\n[!] %s\n" "$*" >&2; }
die()  { printf "\n[✗] %s\n" "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

date
msg "Infra-Labs Phase 1 Finalization v2 starting"
msg "Hostname: ${HV_HOSTNAME}"
msg "IP mode: ${IP_METHOD} ${IP_METHOD=manual:+(${STATIC_IP}/${NETMASK_BITS} gw ${GATEWAY})}"
msg "Log file: ${LOG}"

# ---------- 0. Pre-flight ----------
need ip
if ! command -v nmcli >/dev/null 2>&1; then
  msg "Installing NetworkManager..."
  sudo apt update -y && sudo apt install -y network-manager
fi
need nmcli
if ! command -v virsh >/dev/null 2>&1; then
  msg "Installing libvirt clients..."
  sudo apt update -y && sudo apt install -y libvirt-clients
fi

# ---------- 1. System Update & Core Packages ----------
msg "Updating system & installing core packages..."
sudo apt update -y
sudo apt full-upgrade -y
sudo apt install -y \
  qemu-system-x86 qemu-utils \
  libvirt-daemon libvirt-daemon-system libvirt-daemon-driver-qemu libvirt-clients \
  virtinst bridge-utils cloud-image-utils qemu-guest-agent \
  network-manager ufw fail2ban \
  net-tools curl wget vim git unzip

# ---------- 2. Enable KVM/libvirt stack ----------
msg "Enabling virtualization services..."
sudo systemctl enable --now libvirtd.socket || sudo systemctl enable --now libvirtd
sudo systemctl enable --now virtlogd.socket || true
sudo systemctl enable --now virtlockd.socket || true
sudo usermod -aG libvirt,kvm "$USER" || true

# ---------- 3. Discover interfaces & NM connection ----------
msg "Detecting wired interface and NetworkManager connection..."
# Prefer a connected Ethernet device per nmcli; fallback to 'ip'
ETHER_IFACE="$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}')"
if [[ -z "${ETHER_IFACE}" ]]; then
  ETHER_IFACE="$(ip -br link | awk '/UP/ && $1!="lo"{print $1; exit}')"
fi
[[ -n "${ETHER_IFACE}" ]] || die "Could not detect an active non-loopback interface."

# Find the NM Connection name bound to this device
CON_NAME="$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v dev="$ETHER_IFACE" '$2==dev{print $1; exit}')"

if [[ -z "${CON_NAME}" ]]; then
  warn "No NetworkManager connection profile found for ${ETHER_IFACE}. Creating one..."
  CON_NAME="static-${ETHER_IFACE}"
  sudo nmcli con add type ethernet ifname "${ETHER_IFACE}" con-name "${CON_NAME}"
else
  msg "Found NM connection: '${CON_NAME}' on device '${ETHER_IFACE}'"
fi

# ---------- 4. (Optional) turn Wi-Fi off for stability ----------
if [[ "${DISABLE_WIFI}" == "true" ]]; then
  if nmcli radio wifi >/dev/null 2>&1; then
    msg "Disabling Wi-Fi radio (can be re-enabled with 'nmcli radio wifi on')"
    sudo nmcli radio wifi off || true
  fi
fi

# ---------- 5. Configure IPv4 (manual static or auto DHCP) ----------
if [[ "${IP_METHOD}" == "auto" ]]; then
  msg "Configuring '${CON_NAME}' for DHCP (ipv4.method auto)"
  sudo nmcli con mod "${CON_NAME}" ipv4.method auto
  # Clear static settings if they existed
  sudo nmcli con mod "${CON_NAME}" -ipv4.addresses "" || true
  sudo nmcli con mod "${CON_NAME}" -ipv4.gateway "" || true
  sudo nmcli con mod "${CON_NAME}" ipv4.dns "" || true
else
  [[ -n "${STATIC_IP}" && -n "${GATEWAY}" ]] || die "STATIC_IP and GATEWAY must be set for manual mode."
  msg "Applying STATIC IPv4 to '${CON_NAME}' → ${STATIC_IP}/${NETMASK_BITS}, gw ${GATEWAY}, dns '${DNS_SERVERS}'"
  sudo nmcli con mod "${CON_NAME}" ipv4.method manual
  sudo nmcli con mod "${CON_NAME}" ipv4.addresses "${STATIC_IP}/${NETMASK_BITS}"
  sudo nmcli con mod "${CON_NAME}" ipv4.gateway "${GATEWAY}"
  sudo nmcli con mod "${CON_NAME}" ipv4.dns "${DNS_SERVERS}"
fi

sudo nmcli con mod "${CON_NAME}" connection.autoconnect yes

msg "Cycling connection to apply changes..."
sudo nmcli con down "${CON_NAME}" || true
sleep 1
sudo nmcli con up   "${CON_NAME}"

# ---------- 6. Show IP and test basic reachability ----------
CUR_IP="$(ip -4 addr show "${ETHER_IFACE}" | awk '/inet /{print $2}' | head -n1)"
msg "Current IPv4 on ${ETHER_IFACE} = ${CUR_IP:-unknown}"
if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
  msg "Outbound ping to 1.1.1.1 OK"
else
  warn "Outbound ping failed. If you just switched IP modes, this can be transient."
fi

# ---------- 7. Hostname ----------
msg "Setting hostname to '${HV_HOSTNAME}' and updating /etc/hosts..."
sudo hostnamectl set-hostname "${HV_HOSTNAME}"
if grep -qE '^127\.0\.1\.1\s+' /etc/hosts; then
  sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1   ${HV_HOSTNAME}/" /etc/hosts
else
  echo "127.0.1.1   ${HV_HOSTNAME}" | sudo tee -a /etc/hosts >/dev/null
fi

# ---------- 8. UFW firewall ----------
msg "Configuring UFW..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw --force enable
sudo ufw status verbose | sed 's/^/    /'

# ---------- 9. Fail2ban ----------
msg "Configuring Fail2ban (basic SSH jail)..."
sudo systemctl enable --now fail2ban
sudo mkdir -p /etc/fail2ban/jail.d
sudo tee /etc/fail2ban/jail.d/10-sshd.local >/dev/null <<'JAIL'
[sshd]
enabled   = true
port      = ssh
logpath   = /var/log/auth.log
bantime   = 1h
findtime  = 10m
maxretry  = 5
JAIL
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd || true

# ---------- 10. SSH hardening ----------
msg "Hardening SSH (disable password login & root login)..."
sudo sed -i 's/^[# ]*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^[# ]*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# ---------- 11. Lab directories ----------
msg "Creating lab directories..."
sudo mkdir -p /opt/lab/{isos,images,configs,snapshots,logs}
sudo chown -R "$USER":"$USER" /opt/lab
echo "export LAB_HOME=/opt/lab" | sudo tee /etc/profile.d/lab_home.sh >/dev/null

# ---------- 12. Verify KVM/libvirt ----------
msg "Verifying libvirt connectivity..."
sudo virsh -c qemu:///system list --all || true
sudo virsh net-list --all || true

# ---------- 13. Baseline marker & summary ----------
BASELINE="/opt/lab/snapshots/baseline-info.txt"
cat | sudo tee "${BASELINE}" >/dev/null <<EOF
Infra-Labs baseline v2 completed on $(date)
Hostname: ${HV_HOSTNAME}
Device:   ${ETHER_IFACE}
Conn:     ${CON_NAME}
IP mode:  ${IP_METHOD}
Address:  $(ip -4 addr show "${ETHER_IFACE}" | awk '/inet /{print $2}' | head -n1)
EOF

msg "===== Health Summary ====="
echo "  Hostname:        $(hostnamectl --static)"
echo "  Interface:       ${ETHER_IFACE}"
echo "  NM Connection:   ${CON_NAME}"
echo "  Address:         $(ip -4 addr show "${ETHER_IFACE}" | awk '/inet /{print $2}' | head -n1)"
echo "  Default route:   $(ip route | awk '/default/ {print $0; exit}')"
echo "  UFW:             $(sudo ufw status | head -n1)"
echo "  Fail2ban:        $(systemctl is-active fail2ban)"
echo "  Lab baseline:    ${BASELINE}"
msg "Phase 1 finalization v2 complete. Full log: ${LOG}"
