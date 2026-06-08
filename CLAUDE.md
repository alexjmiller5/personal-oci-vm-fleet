# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fleet config for ONE OCI Always Free ARM VM. Three responsibilities only:

1. **Terraform state** for the VM (VCN, subnet, IGW, instance) via the reusable module at `git::github.com/alexjmiller5/nixos-ocp-tailscale-vm-iac//terraform/oci-vm`.
2. **NixOS flake** that composes:
   - `iac.nixosModules.base` (SSH, tailscale daemon, firewall)
   - `burndown.nixosModules.default` (the burndown service + hermetic build)
   - Future service modules added the same way
3. **Deploy mechanics** (justfile recipes): oci-auth, mint-tailscale-key, terraform plan/apply/destroy, install-infect, fetch-hardware-config, update-nixos, set-secret, status/logs.

Service repos (`notion-task-burndown-chart`, future) export `nixosModules.default` + `packages.<system>.default`. They know nothing about this VM or any other consumer.

## VM Details

- OCI region: `us-ashburn-1`
- Shape: `VM.Standard.A1.Flex` — 1 OCPU / 6 GB RAM / 50 GB boot (Always Free)
- Hostname: `personal-oci-vm`
- Tailnet URL: `https://personal-oci-vm.tailee59b5.ts.net`
- Exposed via `tailscale serve --https=443` (tailnet-only — not public funnel)
- Tailscale tag: `tag:oauth-generated` (per global CLAUDE.md)

## Deploy recipes (justfile)

```bash
just oci-auth              # refresh OCI SecurityToken (browser flow)
just mint-tailscale-key    # 1Password OAuth → secrets.nix (mode 600)
just plan / apply / destroy / ip
just ssh / ssh-ubuntu
just install-infect        # convert fresh Ubuntu instance to NixOS via nixos-infect
just fetch-hardware-config # after first boot: scp /etc/nixos/hardware-configuration.nix back
just update-nixos          # rsync flake + secrets → nixos-rebuild switch
just set-secret            # push NOTION_API_KEY → /etc/burndown.env
just deploy-bootstrap      # first-time: mint-key → apply → wait → install-infect → poll
just logs / status
```

The `install-infect` recipe is hardened: it `cloud-init status --wait`s, force-overrides `/etc/resolv.conf` with public DNS (OCI's freshly-provisioned systemd-resolved is sometimes broken), verifies connectivity to `raw.githubusercontent.com`, runs nixos-infect with `set -o pipefail` so a curl failure aborts the install, and polls for the VM to come back as NixOS before reporting success.

## Adding a new service

1. The new service has its own repo with `nix/flake.nix` exporting `nixosModules.default` and `packages.<sys>.default`.
2. In this repo's `flake.nix`:
   - Add a flake input: `<svc>.url = "github:alexjmiller5/<svc-repo>?dir=nix";`
   - Add to the modules list: `<svc>.nixosModules.default`
   - Add to the inline config block: `services.<svc> = { enable = true; port = ...; origin = ...; };`
3. Resolve port collisions (burndown's loopback is 3000 — pick a different one for the new service).
4. If the new service also needs tailnet HTTPS, decide between different ports (e.g. burndown on 443, svc on 8443) or path-based serving (`tailscale serve --set-path=/svc http://localhost:<port>`).
5. `just update-nixos`.

## Files

- `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tf` — Terraform consuming the iac module
- `flake.nix` — wires base + service modules into `nixosConfigurations.personal-oci-vm`
- `hardware-configuration.nix` — placeholder until first install; real one committed after `fetch-hardware-config`
- `justfile` — deploy recipes
- `.deploy.env.example` → copy to `.deploy.env` (gitignored) — OCI compartment + 1P paths + tailnet name
- `secrets.nix` — Tailscale auth key (gitignored, minted via `just mint-tailscale-key`)

## Key Constraints

- `system.stateVersion` in `hardware-configuration.nix` must remain `25.11` once a VM is installed with that value.
- The OCI compartment OCID in `.deploy.env` is the tenancy root.
- Always Free tier is region-specific (`us-ashburn-1`). On "Out of host capacity" errors, wait and retry — don't switch regions (would invalidate the tailnet hostname registration and OCI naming).
