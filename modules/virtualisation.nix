# modules/virtualisation.nix — libvirt/KVM.
# ПОКА НЕ ИМПОРТИРУЕТСЯ: включать по чек-листу в docs/10-kitjet.md.
# LXC не используем — см. решение в docs/00-Проект.md.
{ config, pkgs, lib, ... }:

{
  virtualisation.libvirtd = {
    enable = true;
    qemu.runAsRoot = false;
    qemu.swtpm.enable = true;          # TPM для гостей, которым он нужен
    qemu.ovmf.enable = true;           # UEFI-прошивка для гостей
  };
  programs.virt-manager.enable = true;

  # Пользователь должен быть в этих группах, иначе virsh просит пароль
  # на каждое действие. Проверка: `groups`.
  users.users.gadjet.extraGroups = [ "libvirtd" "kvm" ];

  # ── Мост br0 ─────────────────────────────────────────────────
  # Нужен, чтобы виртуалки получали адрес из домашней сети, а не NAT.
  # Подставить своё имя интерфейса (`ip link`) и раскомментировать.
  # ОСТОРОЖНО: неверное имя = машина без сети, чинить с клавиатуры.
   networking.networkmanager.unmanaged = [ "enp5s0" ];
   networking.bridges.br0.interfaces = [ "enp5s0" ];
   networking.interfaces.br0.useDHCP = true;
}
