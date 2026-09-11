# hosts/kitjet — кухонный сервер у телевизора, x86_64.
# Здесь только ВЫБОР возможностей (какие modules включены) и то,
# что верно исключительно для этой машины: железо, имя, загрузчик.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/storage.nix           # ZFS-пул tank + samba
    ../../modules/virtualisation.nix    # libvirt/KVM для VM образов
  ];

  networking.hostName = "kitjet";

  # hostId нужен ZFS, чтобы понять, её ли это пул: при импорте он
  # сверяет записанный в пуле hostId с текущим. Уникален на машину,
  # менять нельзя — иначе пул начнёт требовать `zpool import -f`.
  # Значение взято из `head -c 8 /etc/machine-id`.
  networking.hostId = "ab1bac40";

  # ── Загрузка ─────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # boot.kernelPackages здесь НЕ задаётся: ядро выбирает
  # modules/storage.nix, привязывая его к версии ZFS.
  # Вернуть linuxPackages_latest можно только вместе с отказом от ZFS.

  # ── Jellyfin — медиасервер ───────────────────────────────
  # Роль именно этой машины: раздаёт /tank/media на телевизор.
  # Раньше лежал в modules/desktop.nix и приехал бы на любой рабочий
  # стол, включая deskjet. Перенесён сюда 2026-09-11.
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    # Кэш и конфиги — в /var/lib/jellyfin/ (управляется systemd).
    # Медиа-библиотека — в /tank/media (добавляется в веб-интерфейсе).
  };

  # ── Kingston SSD для VM образов ────────────────────────────
  # KINGSTON SA400S37480G, 447 GiB, btrfs
  fileSystems."/var/lib/libvirt/images" = {
    device = "/dev/disk/by-uuid/13c0c7da-ad6f-4331-88e9-06948786d0c0";
    fsType = "btrfs";
    options = [ "defaults" "nofail" ];
  };

  # ── Сборка для Pi ────────────────────────────────────────────
  # Позволяет собирать aarch64 прямо здесь (через qemu-user), чтобы не
  # компилировать на самой малине. Раскомментировать перед установкой rpinix.
  # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Маркер формата данных, а не версия ОС. НЕ МЕНЯТЬ НИКОГДА.
  system.stateVersion = "26.05";
}
