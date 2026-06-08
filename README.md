# personal-oci-vm-fleet

Fleet config for one OCI Always Free ARM VM (`us-ashburn-1`, 1 OCPU / 6 GB / 50 GB), running a NixOS composition of:

- [`nixos-ocp-tailscale-vm-iac`](https://github.com/alexjmiller5/nixos-ocp-tailscale-vm-iac) — base: SSH, tailscale daemon, firewall
- [`notion-task-burndown-chart`](https://github.com/alexjmiller5/notion-task-burndown-chart) (`?dir=nix`) — burndown service module + hermetic build
- Future service modules (added as flake inputs)

Each service repo stays a pure NixOS-module + build flake. This repo owns the VM-specific composition, Terraform state, deploy mechanics, and secret push.

## First deploy

```bash
cp .deploy.env.example .deploy.env   # if you fork, otherwise the existing values are fine
just oci-auth                        # one-time per session — browser flow
just deploy-bootstrap                # mint-tailscale-key → terraform apply → nixos-infect → poll
just fetch-hardware-config           # scp real hardware-configuration.nix back
just update-nixos                    # rsync flake → nixos-rebuild switch
just set-secret                      # push NOTION_API_KEY → /etc/burndown.env (mode 600)
```

After deploy: <https://personal-oci-vm.tailee59b5.ts.net>

## Routine updates

```bash
just oci-auth        # if session expired
just update-nixos    # rsync local flake + nixos-rebuild switch
just status          # service + tailscale state
just logs            # journalctl follow
```

To bump a service flake input (e.g. burndown):

```bash
nix flake update burndown   # bumps the input in flake.lock
just update-nixos           # ships the new lock + rebuilds
```

## Architecture

See `CLAUDE.md`.
