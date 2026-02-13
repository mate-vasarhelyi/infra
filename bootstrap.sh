#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/mate-vasarhelyi/infra.git"
CLONE_DIR="$HOME/.infra"

echo "=== Config Empire Bootstrap ==="

# Detect distro and install prerequisites
if command -v pacman &>/dev/null; then
    sudo pacman -Syu --noconfirm git ansible
elif command -v apt &>/dev/null; then
    sudo apt update && sudo apt full-upgrade -y && sudo apt install -y git ansible
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
