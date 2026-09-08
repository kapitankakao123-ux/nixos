# hosts/rpinix — Raspberry Pi 5 (BCM2712), aarch64.
#
# ЭТАП 1: минимальная загружаемая система. Sway, контейнеры и оптимизация
# батареи намеренно отключены — сначала добиваемся загрузки с NVMe,
# потом наращиваем по одному модулю. Разбор в docs/11-rpinix.md.
#
# Загрузка Pi 5 устроена не как на x86:
#   EEPROM → раздел FIRMWARE (vfat) → config.txt → kernel.img напрямую.
# U-Boot и extlinux здесь НЕ участвуют: ubootRaspberryPi5 в nixpkgs
# не существует, а raspberry-pi-nix при uboot.enable = false (по умолчанию)
# кладёт ядро прямо в раздел прошивки — это и есть штатный путь для NVMe.
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../modules/common.nix
    # Включать по одному ПОСЛЕ первой успешной загрузки:
    # ../../modules/desktop-light.nix        # Sway на 7" DSI
    # ../../modules/battery-optimization.nix # питание (проверить tlp на ARM)
    # ../../modules/container.nix            # Podman
  ];

  # ── Плата ────────────────────────────────────────────────
  # bcm2712 = Pi 5 / Pi 500 / CM5. bcm2711 — это Pi 4.
  raspberry-pi-nix.board = "bcm2712";

  # kernel-version намеренно оставлен по умолчанию: под него собраны
  # бинарники в nix-community.cachix.org. Поменяешь — будешь компилировать
  # ядро на самой малине несколько часов.

  networking.hostName = "rpinix";

  # ── TPM в initrd ─────────────────────────────────────────
  # nixpkgs добавляет в initrd модули tpm-tis и tpm-crb для всего, кроме
  # riscv64 и armv7 (nixos/modules/system/boot/systemd/tpm2.nix). aarch64 под
  # исключение не попадает, а вендорное ядро Raspberry Pi модуль tpm-crb не
  # собирает → сборка initrd падает на "modprobe: FATAL: Module tpm-crb not found".
  # На Pi 5 TPM нет физически, так что просто выключаем.
  boot.initrd.systemd.tpm2.enable = false;

  # hardware-configuration.nix здесь НЕ импортируется и fileSystems не
  # задаются: разметку (FIRMWARE + NIXOS_SD) описывает модуль sd-image.

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

  # Совпадает с веткой nixpkgs, на которой собирается этот flake (26.05).
  system.stateVersion = "26.05";
}
