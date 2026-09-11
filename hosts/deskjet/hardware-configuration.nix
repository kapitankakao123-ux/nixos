# hosts/deskjet/hardware-configuration.nix — железо домашнего ПК.
#
# Написан вручную по данным с живого Arch (2026-09-11), а не через
# nixos-generate-config. При установке сверить с его выводом:
#   nixos-generate-config --root /mnt --show-hardware-config
#
# Ryzen 7 5700X, 31 ГБ, Radeon RX 9060 XT (Navi 44, RDNA4),
# Realtek RTL8111 (r8169), один NVMe на 1 ТБ, загрузка UEFI.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # ── Разделы ──────────────────────────────────────────────
  # Один NVMe, три раздела. При установке переформатируются ТОЛЬКО p1 и p2.
  # p3 с домашней папкой (542 ГБ, из них 374 ГБ игр и 109 ГБ Steam)
  # остаётся как есть — вместе со всеми настройками, ключами и профилями.
  #
  #   nvme0n1p1    1 ГБ  vfat   → /boot   ФОРМАТИРУЕТСЯ, метка BOOT
  #   nvme0n1p2   50 ГБ  btrfs  → /       ФОРМАТИРУЕТСЯ, метка deskjet
  #   nvme0n1p3  903 ГБ  btrfs  → /home   НЕ ТРОГАЕТСЯ, по UUID
  #
  # Для p1 и p2 — метки, а не UUID: после mkfs UUID будут новыми, а метки
  # мы задаём сами, так что конфиг можно написать и проверить заранее.

  fileSystems."/" = {
    device = "/dev/disk/by-label/deskjet";
    fsType = "btrfs";
    # Те же опции, что были на Arch: сжатие zstd:3 и асинхронный TRIM.
    # noatime вместо relatime — меньше лишних записей на SSD.
    options = [ "compress=zstd:3" "noatime" "discard=async" "space_cache=v2" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    # Загрузочный раздел читает только root: там ядра и initrd.
    options = [ "fmask=0077" "dmask=0077" ];
  };

  fileSystems."/home" = {
    # ОБЯЗАТЕЛЬНО UUID: это существующий раздел с данными.
    # Сверено с lsblk на Arch 2026-09-11.
    device = "/dev/disk/by-uuid/be7721f1-df08-4875-8b84-562b78cc4536";
    fsType = "btrfs";
    # Подтомов нет — /home это корень раздела (subvolid=5), как на Arch.
    options = [ "compress=zstd:3" "noatime" "discard=async" "space_cache=v2" ];
  };

  swapDevices = [ ];   # swap — через zram, см. default.nix

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
