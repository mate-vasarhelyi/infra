# NVM Role Design

## Goal

Add nvm (Node Version Manager) and LTS Node.js to the `env` tag so all managed systems get a working Node.js environment.

## Decisions

- **Install method:** Official curl install script (`https://raw.githubusercontent.com/nvm-sh/nvm/v<version>/install.sh`)
- **Version pinning:** `nvm_version` variable in `defaults/main.yml`, bumped manually
- **Idempotency:** `creates: ~/.nvm/nvm.sh` skips reinstall; node install checks if LTS already present
- **Shell integration:** Sourcing block added to existing `roles/zsh/templates/zshrc.j2`
- **Tags:** `[env, setup]` — both existing and new systems get nvm + LTS node
- **No global npm packages** for now

## Role Structure

```
roles/nvm/
├── defaults/main.yml    # nvm_version
└── tasks/main.yml       # Install nvm + LTS node
```

## Changes

1. **New role `roles/nvm/`** — install nvm via curl script, install LTS node
2. **Modify `roles/zsh/templates/zshrc.j2`** — add nvm sourcing block
3. **Modify `site.yml`** — add nvm role with `[env, setup]` tags after zsh
4. **Update `CLAUDE.md`** — add nvm to env tag table
