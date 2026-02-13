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
        grep -q "^DownloadUser" /etc/pacman.conf || $SUDO sed -i '/^\[options\]/a DownloadUser = root' /etc/pacman.conf
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

echo ""
echo "Ready! Run your playbook:"
echo "  cd $CLONE_DIR"
echo "  ansible-playbook site.yml --tags common,desktop --ask-vault-pass"
