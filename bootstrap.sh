#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/mate-vasarhelyi/infra.git"
CLONE_DIR="$HOME/.infra"

echo "=== Config Empire Bootstrap ==="

# Use sudo only if not root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

# Detect distro and install prerequisites
if command -v pacman &>/dev/null; then
    $SUDO pacman-key --init
    $SUDO pacman-key --populate archlinux
    # Disable Landlock sandbox in containers (pacman 7.x)
    if [ -f /run/.containerenv ] || grep -q container=lxc /proc/1/environ 2>/dev/null || systemd-detect-virt -c &>/dev/null; then
        grep -q "^DisableSandbox" /etc/pacman.conf || $SUDO sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
    fi
    $SUDO pacman -Sy --noconfirm archlinux-keyring
    $SUDO pacman -Su --noconfirm git ansible
elif command -v apt &>/dev/null; then
    $SUDO apt update && $SUDO apt full-upgrade -y && $SUDO apt install -y git ansible
elif command -v brew &>/dev/null; then
    brew install git ansible
else
    echo "Unsupported package manager. Install git and ansible manually."
    exit 1
fi

# Clone the repo
if [ -d "$CLONE_DIR" ]; then
    echo "Repo already exists at $CLONE_DIR, pulling latest..."
    git -C "$CLONE_DIR" pull
else
    git clone "$REPO" "$CLONE_DIR"
fi

cd "$CLONE_DIR"

# Install ansible galaxy dependencies
if [ -f requirements.yml ]; then
    ansible-galaxy collection install -r requirements.yml
fi

# Set up vault password
if [ ! -f "$CLONE_DIR/.vault-pass" ]; then
    read -rsp "Ansible vault password: " vault_pass </dev/tty
    echo
    echo "$vault_pass" > "$CLONE_DIR/.vault-pass"
    chmod 600 "$CLONE_DIR/.vault-pass"
fi

echo ""
echo "=== Bootstrap complete ==="
echo ""
read -rp "Run the playbook now? [y/N] " run_now </dev/tty
if [[ "$run_now" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Which tags?"
    echo "  1) env    — packages + config for current user"
    echo "  2) setup  — create user + full env (new systems)"
    echo "  3) custom — enter your own tags"
    echo ""
    read -rp "Choice [1/2/3]: " tag_choice </dev/tty
    case "$tag_choice" in
        1) tags="env" ;;
        2) tags="setup" ;;
        3)
            read -rp "Enter tags (comma-separated): " tags </dev/tty
            ;;
        *)
            echo "Invalid choice, exiting."
            exit 1
            ;;
    esac
    echo ""
    echo "Privilege escalation method?"
    echo "  1) sudo — use your user password (most systems)"
    echo "  2) su   — use the root password (Arch with fprintd)"
    echo ""
    read -rp "Choice [1/2]: " become_choice </dev/tty
    case "$become_choice" in
        1) become_method="sudo" ;;
        2) become_method="su" ;;
        *)
            echo "Invalid choice, exiting."
            exit 1
            ;;
    esac
    echo ""
    echo "Running: ansible-playbook site.yml --tags $tags --ask-become-pass -e ansible_become_method=$become_method"
    echo ""
    ansible-playbook site.yml --tags "$tags" --ask-become-pass -e "ansible_become_method=$become_method"
else
    echo ""
    echo "Ready! Run your playbook:"
    echo "  cd $CLONE_DIR"
    echo "  ansible-playbook site.yml --tags env --ask-become-pass    # existing system"
    echo "  ansible-playbook site.yml --tags setup --ask-become-pass  # new system"
    echo ""
    echo "Add -e ansible_become_method=sudo if su fails (default is su from ansible.cfg)"
fi
