set dotenv-load := true
set dotenv-filename := ".deploy.env"

default:
  @just --list

# OCI auth — refresh expiring SecurityToken.
oci-auth:
  oci session authenticate --region us-ashburn-1 --profile-name DEFAULT

# Mint a Tailscale auth key via OAuth (1Password) and write secrets.nix.
mint-tailscale-key:
  #!/usr/bin/env bash
  set -euo pipefail
  CLIENT_ID=$(op read "$TS_OAUTH_ID_PATH")
  CLIENT_SECRET=$(op read "$TS_OAUTH_SECRET_PATH")
  TOKEN=$(curl -fsS \
    -d "client_id=$CLIENT_ID" -d "client_secret=$CLIENT_SECRET" \
    https://api.tailscale.com/api/v2/oauth/token | jq -r .access_token)
  AUTH_KEY=$(curl -fsS -X POST \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":false,"preauthorized":true,"tags":["tag:oauth-generated"]}}},"expirySeconds":7776000}' \
    https://api.tailscale.com/api/v2/tailnet/-/keys | jq -r .key)
  printf '{ tailscaleAuthKey = "%s"; }\n' "$AUTH_KEY" > secrets.nix
  chmod 600 secrets.nix
  echo "✓ secrets.nix written (mode 600)."

# Terraform wrappers.
init:
  terraform init
plan:
  terraform plan -var="compartment_id=$OCI_COMPARTMENT_ID"
apply:
  terraform apply -var="compartment_id=$OCI_COMPARTMENT_ID"
destroy:
  terraform destroy -var="compartment_id=$OCI_COMPARTMENT_ID"
ip:
  @terraform output -raw instance_public_ip

# SSH into the freshly-provisioned Ubuntu instance (pre-nixos-infect).
ssh-ubuntu:
  #!/usr/bin/env bash
  IP=$(terraform output -raw instance_public_ip)
  ssh ubuntu@$IP

# SSH as root (post-NixOS).
ssh:
  #!/usr/bin/env bash
  IP=$(terraform output -raw instance_public_ip)
  ssh root@$IP

# Install NixOS via nixos-infect on the freshly-provisioned Ubuntu host.
# Resilient version: waits for cloud-init, forces working DNS, sets pipefail
# on the remote pipeline, and polls for the VM to come back as NixOS.
install-infect:
  #!/usr/bin/env bash
  set -euo pipefail
  IP=$(terraform output -raw instance_public_ip)

  echo "==> Waiting for cloud-init to finish (max ~3 min)..."
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 ubuntu@$IP 'sudo cloud-init status --wait' || true

  echo "==> Forcing reliable DNS (some OCI Ubuntu VMs ship with broken systemd-resolved)..."
  ssh ubuntu@$IP "sudo bash -c 'echo nameserver 8.8.8.8 > /etc/resolv.conf; echo nameserver 1.1.1.1 >> /etc/resolv.conf'"
  if ! ssh ubuntu@$IP 'curl -fsS --max-time 15 -o /dev/null https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect'; then
    echo "✗ Cannot reach raw.githubusercontent.com after DNS fix — aborting"
    exit 1
  fi
  echo "✓ Connectivity verified"

  echo "==> Staging /etc/nixos/ on the instance (flake + secrets for the post-infect update-nixos step)..."
  ssh ubuntu@$IP 'sudo mkdir -p /etc/nixos'
  rsync -av --exclude='.terraform' --exclude='.terraform.lock.hcl' --exclude='terraform.tfstate*' --exclude='*.tfvars' \
    ./ ubuntu@$IP:/tmp/fleet-deploy/
  ssh ubuntu@$IP 'sudo cp -r /tmp/fleet-deploy/. /etc/nixos/ && sudo chown -R root:root /etc/nixos && sudo chmod 600 /etc/nixos/secrets.nix 2>/dev/null || true'

  echo "==> Running nixos-infect (SSH will drop on reboot — that's expected)..."
  ssh ubuntu@$IP "set -o pipefail; curl -fsSL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | sudo NIX_CHANNEL=nixos-unstable bash -x 2>&1 | sudo tee /tmp/infect.log | tail -20" \
    || echo "(SSH disconnected — checking if reboot succeeded...)"

  echo "==> Waiting for VM to come back as NixOS (max ~5 min)..."
  sleep 60
  for i in $(seq 1 30); do
    if ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes root@$IP 'cat /etc/os-release 2>/dev/null' 2>/dev/null | grep -q '^NAME="NixOS"'; then
      echo "✓ VM is up and running NixOS"
      echo "  Next: just fetch-hardware-config && just update-nixos && just set-secret"
      exit 0
    fi
    sleep 10
  done
  echo "✗ VM did not come back as NixOS within 5 minutes."
  echo "  Check OCI console serial output."
  exit 1

# Copy hardware-configuration.nix back from the VM after first install.
fetch-hardware-config:
  #!/usr/bin/env bash
  set -euo pipefail
  IP=$(terraform output -raw instance_public_ip)
  scp root@$IP:/etc/nixos/hardware-configuration.nix .
  echo "✓ hardware-configuration.nix saved. Commit and run 'just update-nixos'."

# Rsync flake + secrets, then nixos-rebuild switch on the VM.
update-nixos:
  #!/usr/bin/env bash
  set -euo pipefail
  IP=$(terraform output -raw instance_public_ip)
  rsync -av --exclude='.terraform' --exclude='.terraform.lock.hcl' --exclude='terraform.tfstate*' --exclude='*.tfvars' \
    ./ root@$IP:/etc/nixos/
  ssh root@$IP "chmod 600 /etc/nixos/secrets.nix 2>/dev/null || true; cd /etc/nixos && nixos-rebuild switch --flake .#personal-oci-vm"

# Push the Notion API key from 1Password to /etc/burndown.env (mode 600).
set-secret:
  #!/usr/bin/env bash
  set -euo pipefail
  IP=$(terraform output -raw instance_public_ip)
  KEY=$(op read "$SECRET_PATH")
  printf 'NOTION_API_KEY=%s\n' "$KEY" | \
    ssh root@$IP "tee /etc/burndown.env > /dev/null && chmod 600 /etc/burndown.env"
  ssh root@$IP "systemctl try-restart burndown.service" || true
  echo "✓ Secret installed."

# Full first-deploy.
deploy-bootstrap: mint-tailscale-key apply
  @echo "==> Waiting 60s for instance to boot..."
  sleep 60
  just install-infect
  @echo ""
  @echo "==> Run next:"
  @echo "    just fetch-hardware-config"
  @echo "    just update-nixos"
  @echo "    just set-secret"

logs:
  #!/usr/bin/env bash
  IP=$(terraform output -raw instance_public_ip)
  ssh root@$IP "journalctl -u burndown.service -f -n 50"

status:
  #!/usr/bin/env bash
  IP=$(terraform output -raw instance_public_ip)
  ssh root@$IP "systemctl status burndown.service --no-pager; echo; tailscale status; echo; tailscale serve status"
