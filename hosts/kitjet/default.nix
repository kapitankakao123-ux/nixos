# hosts/kitjet — кухонный сервер у телевизора, x86_64.
# Здесь только ВЫБОР возможностей (какие modules включены) и то,
# что верно исключительно для этой машины: железо, имя, загрузчик.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    # Включать по чек-листам в docs/10-kitjet.md, по одному за раз:
    # ../../modules/storage.nix          # ZFS + samba (см. предупреждение про ядро внутри)
    # ../../modules/virtualisation.nix   # libvirt/KVM
  ];

  networking.hostName = "kitjet";

  # hostId нужен ZFS, чтобы понять, её ли это пул. Уникален на машину.
  # Раскомментировать вместе с modules/storage.nix. Значение — 8 hex-символов,
  # взять из `head -c 8 /etc/machine-id` и больше НИКОГДА не менять.
  # networking.hostId = "";

  # ── Загрузка ─────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ── Сборка для Pi ────────────────────────────────────────────
  # Позволяет собирать aarch64 прямо здесь (через qemu-user), чтобы не
  # компилировать на самой малине. Раскомментировать перед установкой rpinix.
  # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Маркер формата данных, а не версия ОС. НЕ МЕНЯТЬ НИКОГДА.
  system.stateVersion = "26.05";
}
