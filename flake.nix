{
  description = "personal-oci-vm — fleet config for one OCI Always Free ARM VM; wires iac base + service modules";

  inputs = {
    nixpkgs.url   = "github:NixOS/nixpkgs/nixos-unstable";
    iac.url       = "github:alexjmiller5/nixos-ocp-tailscale-vm-iac";
    burndown.url  = "github:alexjmiller5/notion-task-burndown-chart?dir=nix";
    # Add future service modules here:
    # newservice.url = "github:alexjmiller5/new-service?dir=nix";
  };

  outputs = { self, nixpkgs, iac, burndown, ... }: {
    nixosConfigurations.personal-oci-vm =
      nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./hardware-configuration.nix
          iac.nixosModules.base
          burndown.nixosModules.default
          # newservice.nixosModules.default

          ({ ... }: {
            networking.hostName = "personal-oci-vm";
            time.timeZone = "America/New_York";

            services.burndown = {
              enable = true;
              origin = "https://personal-oci-vm.tailee59b5.ts.net";
              # default port 3000, tailscale serve on :443
            };

            # services.newservice = { enable = true; port = 3001; ... };
          })
        ];
      };
  };
}
