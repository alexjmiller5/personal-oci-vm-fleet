{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  # placeholder — replaced by `just fetch-hardware-config` after first install
  boot.loader.grub.device = "nodev";
  fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
  system.stateVersion = "25.11";
}
