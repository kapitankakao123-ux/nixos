# hosts/rpinix — Raspberry Pi 5 портативное устройство, aarch64.
# 7" DSI-дисплей, батареи, NVMe, Sway, контейнеры.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop-light.nix   # Sway для 7" DSI-дисплея
    ../../modules/battery-optimization.nix
    ../../modules/container.nix
  ];

  networking.hostName = "rpinix";
  # networking.hostId = "";  # заполнить: head -c 8 /etc/machine-id на Pi после первой загрузки

  # ── Загрузчик для Pi5 ──────────────────────────────────
  # generic-extlinux-compatible работает на любых ARM устройствах,
  # включая Pi5. boot.loader.raspberryPi удалён в nixpkgs.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # ── Ядро ───────────────────────────────────────────────
  # Pi5 нужно современное ядро с поддержкой ARM64v8.
  boot.kernelPackages = pkgs.linuxPackages_6_6;

  boot.kernelParams = [
    "cma=256M"        # CMA для GPU/DSI
  ];

  boot.kernelModules = [ "vc4" ];  # VideoCore IV для дисплея

  # ── Сеть ───────────────────────────────────────────────
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = true;  # TODO: выключить, когда добавишь ключ
      PermitRootLogin = "yes";       # TODO: выключить после первой настройки
    };
  };

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── Файловая система ───────────────────────────────────
  # Ставится на /dev/nvme0n1 (238 ГБ NVMe на Pi5)
  fileSystems."/" = {
    device = "/dev/nvme0n1";
    fsType = "btrfs";
    options = [ "defaults" ];
  };

  # ── Отключить конфликтующий wireless ───────────────────
  # NetworkManager пытается включить wireless, но iwd это делает
  networking.wireless.enable = lib.mkForce false;

  # Маркер формата данных. НЕ МЕНЯТЬ.
  system.stateVersion = "26.11";
}
