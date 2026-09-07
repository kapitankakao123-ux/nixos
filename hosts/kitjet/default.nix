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
    # ../../modules/virtualisation.nix  # libvirt/KVM — по чек-листу в docs/10-kitjet.md
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

  # ── Сборка для Pi ────────────────────────────────────────────
  # Позволяет собирать aarch64 прямо здесь (через qemu-user), чтобы не
  # компилировать на самой малине. Раскомментировать перед установкой rpinix.
  # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Маркер формата данных, а не версия ОС. НЕ МЕНЯТЬ НИКОГДА.
  system.stateVersion = "26.05";
}
