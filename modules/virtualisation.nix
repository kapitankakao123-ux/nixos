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
  
  virtualisation.oci-containers = {
    backend = "podman";
    containers.homeassistant = {
      volumes = [ "home-assistant:/config" ];
      environment.TZ = "Europe/Berlin";
      image = "ghcr.io/home-assistant/home-assistant:stable"; # Warning: if the tag does not change, the image will not be updated
      extraOptions = [ 
        "--network=host" 
        "--device=/dev/ttyACM0:/dev/ttyACM0"  # Example, change this to match your own hardware
      ];
    };
  };

  services.home-assistant = {
    # opt-out from declarative configuration management
    config = null;
    lovelaceConfig = null;
    # configure the path to your config directory
    configDir = "/etc/home-assistant";
    # specify list of components required by your configuration
    extraComponents = [
      "esphome"
      "met"
      "radio_browser"
    ];
  };

}
