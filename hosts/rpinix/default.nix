# hosts/rpinix — Raspberry Pi 5 (BCM2712), aarch64.
#
# ЭТАП 1: минимально загружаемая система. Sway, контейнеры и оптимизация
# батареи намеренно отключены — сначала добиваемся загрузки с NVMe,
# потом наращиваем по одному модулю. Разбор в docs/11-rpinix.md.
#
# Собирается из nixpkgs-unstable (см. flake.nix): только там sd-image-aarch64
# знает про Pi 5. Схема загрузки — штатная для этого образа:
#   EEPROM → раздел FIRMWARE (vfat) → config.txt → u-boot.bin
#          → extlinux.conf на корне → ядро + initrd
# Это ровно то, чем грузится live-система с SD, то есть путь проверен
# на этом самом железе.
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common.nix
    # Включать по одному ПОСЛЕ первой успешной загрузки:
    # ../../modules/desktop-light.nix        # Sway на 7" DSI
    # ../../modules/battery-optimization.nix # питание (проверить tlp на ARM)
    # ../../modules/container.nix            # Podman
  ];

  networking.hostName = "rpinix";

  # ── Метки и ID разделов ──────────────────────────────────
  # По умолчанию sd-image даёт ВСЕМ образам одинаковые метки (FIRMWARE,
  # NIXOS_SD) и одинаковый firmwarePartitionID (0x2178694e). Из-за этого
  # SD-карта и NVMe становятся неразличимы: root=PARTUUID=…-02 и
  # /dev/disk/by-label/NIXOS_SD указывают неизвестно на какой из дисков,
  # если вставлены оба. Проверено на живой машине 2026-09-09.
  # Разводим их явно, чтобы SD можно было держать вставленной.
  sdImage = {
    firmwarePartitionID = "0x52504958";   # "RPIX" в ASCII, лишь бы не 0x2178694e
    firmwarePartitionName = "RPINIXFW";   # метка FAT, максимум 11 символов
    rootVolumeLabel = "RPINIX";           # вместо NIXOS_SD
  };

  # hardware-configuration.nix здесь НЕ импортируется и fileSystems не
  # задаются: разметку описывает модуль sd-image, а корень и /boot/firmware
  # он подставляет сам из меток выше.

  # ── Сеть ─────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = true;  # TODO: выключить после добавления ключа
      PermitRootLogin = "yes";        # TODO: выключить после первой настройки
    };
  };

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Пароль на первую загрузку. Сменить сразу после входа: passwd
  users.users.gadjet.initialPassword = "1414";

  # Не меняется никогда, даже при переходе на другую ветку nixpkgs.
  system.stateVersion = "26.05";
}
