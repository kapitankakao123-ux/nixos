# modules/virtualisation.nix — libvirt/KVM.
# Импортируется kitjet: на нём VM с Home Assistant. См. vault: Машины/kitjet/Home-Assistant.md.
# LXC на NixOS не используем — см. решение в vault: 00-Проект.md.
{ config, pkgs, lib, ... }:

{
  virtualisation.libvirtd = {
    enable = true;
    qemu.runAsRoot = false;
    qemu.swtpm.enable = true;          # TPM для гостей, которым он нужен
    # qemu.ovmf удалён (OVMF теперь по умолчанию)
  };
  programs.virt-manager.enable = true;

  # Пользователь должен быть в этих группах, иначе virsh просит пароль
  # на каждое действие. Проверка: `groups`.
  users.users.gadjet.extraGroups = [ "libvirtd" "kvm" ];

  # ── Мост br0 (опционально) ────────────────────────────────
  # Нужен, чтобы виртуалки получали адрес из домашней сети, а не NAT.
  # Интерфейс: enp5s0. ОСТОРОЖНО: неверное имя = машина без сети.
  # Раскомментировать только если нужен мост:
  networking.networkmanager.unmanaged = [ "enp5s0" ];
  networking.bridges.br0.interfaces = [ "enp5s0" ];
  networking.interfaces.br0.useDHCP = true;

  # ── Здесь НЕТ Home Assistant ──────────────────────────────
  # Раньше в этом файле лежали два блока из вики, оставшиеся от копипасты:
  # `virtualisation.oci-containers.containers.homeassistant` и
  # `services.home-assistant`. Убраны 2026-09-13.
  #
  # Home Assistant на kitjet — это **HAOS в виртуалке** `haos` (см. vault:
  # Машины/kitjet/Home-Assistant.md), и Zigbee-донгл проброшен туда же.
  # Контейнер пытался забрать `/dev/ttyACM0` — устройства с таким именем на
  # kitjet нет вовсе (донгл CP2102 приходит как `/dev/ttyUSB0`), падал с
  # `status=125`, упирался в лимит рестартов и держал систему в `degraded`.
  # Чинить его было нельзя: два HA на один донгл — это конфликт за устройство.
  #
  # Если когда-нибудь понадобится второй HA в контейнере, донгл пробрасывать
  # по устойчивому пути `/dev/serial/by-id/usb-Silicon_Labs_CP2102_*`, а не по
  # номеру `ttyUSB0`: номер меняется от порядка подключения.
}
