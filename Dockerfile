FROM debian:bookworm

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git ansible python3-passlib sudo curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy repo into build context
COPY . /tmp/infra

# Install Ansible Galaxy dependencies
RUN ansible-galaxy collection install -r /tmp/infra/requirements.yml

# Replace encrypted vault with empty file and remove vault_password_file
# reference from ansible.cfg (secrets not needed in Docker)
RUN cd /tmp/infra && \
    echo '---' > group_vars/all/vault.yml && \
    sed -i '/vault_password_file/d' ansible.cfg && \
    ansible-playbook site.yml \
      --tags setup,remote-dev \
      --extra-vars "@docker-defaults.yml" \
      --extra-vars "target_user=dev" \
      --connection=local

# Clean up
RUN apt-get purge -y ansible && \
    apt-get autoremove -y && \
    rm -rf /tmp/infra /var/lib/apt/lists/*

# Copy entrypoint from build context (after /tmp/infra is removed)
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER dev
WORKDIR /home/dev

EXPOSE 8080 7681

ENTRYPOINT ["docker-entrypoint.sh"]
