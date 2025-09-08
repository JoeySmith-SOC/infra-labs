# infra-labs

Terminal-first infrastructure lab for **IAM**, **automation**, and **homelab** projects.  
Built and tested on **laptop (control node)** + **Parrot OS desktop (hypervisor)**.  

---

## 📂 Repository Structure

```
infra-labs/
├── ansible/
│   ├── ansible.cfg              # Ansible configuration
│   ├── inventories/
│   │   └── hosts.ini            # Inventory (laptop + parrot desktop)
│   └── playbooks/
│       ├── 00_ping.yml          # Connectivity test playbook
│       └── 10_prepare_parrot_libvirt.yml  # Hypervisor prep playbook
├── docs/
│   └── ansible-setup.md         # Setup notes (control node)
├── .gitignore
└── README.md
```

---

## 🚀 Quick Start

### Control Node (Laptop)
1. Clone the repo:
   ```bash
   git clone git@github.com:YOUR_GH_USERNAME/infra-labs.git
   cd infra-labs
   ```

2. Create and activate a Python venv:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install --upgrade pip
   pip install "ansible>=9.0.0"
   ansible-galaxy collection install community.general community.libvirt ansible.posix ansible.windows
   ```

3. Verify Ansible sees the inventory:
   ```bash
   ansible-inventory -i ansible/inventories/hosts.ini --graph
   ```

4. Test connectivity:
   ```bash
   ansible -i ansible/inventories/hosts.ini parrot -m ping
   ```

---

### Parrot Desktop (Hypervisor)
- Running Parrot Security OS with virtualization enabled (AMD SVM).  
- Verified with `/dev/kvm` and `virsh -c qemu:///system list --all`.  
- Accessible from laptop via SSH using key-based auth.  

---

## 🛠 Features (current & planned)

- ✅ Working **Ansible control node** on laptop  
- ✅ Inventory file (`hosts.ini`) with Parrot desktop defined  
- ✅ First playbook (`10_prepare_parrot_libvirt.yml`) to prep hypervisor with libvirt/KVM  
- ⏳ Next playbook: **VM creation with cloud images** (Ubuntu/Windows Server)  
- ⏳ Expand into IAM scenarios, AD/Domain Controller, and Chef cookbooks  

---

## 📖 Documentation

- `docs/ansible-setup.md` → how to set up Ansible on control node  
- Future docs: VM provisioning, IAM integration, network diagrams  

---

## 📝 License

[MIT License](LICENSE)
