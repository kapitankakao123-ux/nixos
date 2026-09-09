# hosts/rpinix — Raspberry Pi 5 (BCM2712), aarch64.
#
# ЭТАП 1: минимально загружаемая система. Sway, контейнеры и оптимизация
# батареи намеренно отключены — сначала добиваемся загрузки, потом
# наращиваем по одному модулю. Разбор в docs/11-rpinix.md.
#
# ── ПОЧЕМУ ЗАГРУЗКА С SD, А КОРЕНЬ НА NVMe ───────────────────
# U-Boot из nixpkgs не умеет NVMe: в ubootRaspberryPiAarch64
#     boot_targets=mmc usb pxe dhcp
# NVMe в списке нет, и блочного драйвера тоже нет (отсутствуют строки
# nvme_scan, Identify, Namespace). Переопределять boot_targets бесполезно.
# Проверено разбором бинаря 2026-09-09.
#
# Попытка обойти U-Boot и грузить ядро прошивкой напрямую (как делает
# raspberry-pi-nix) дала чёрный экран — без UART не диагностируется.
#
# Поэтому классическая для Raspberry Pi компоновка: грузимся с SD,
# система живёт на NVMe.
#
#   SD  p1 (vfat, FIRMWARE)  → /boot/firmware — прошивка + u-boot.bin
#   SD  p2 (ext4)            → /boot — extlinux.conf, ядро, initrd
#   NVMe                     → / — вся система, 238 ГБ
#
# Выигрыш против ручной возни с FAT: nixos-rebuild работает штатно,
# ядро на /boot обновляет сам generic-extlinux-compatible.
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

  # ── Разделы ──────────────────────────────────────────────
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/RPINIXROOT";
      fsType = "ext4";
    };

    # Раздел SD, с которого U-Boot читает extlinux.conf.
    # Метка NIXOS_SD осталась от live-образа — переименовать можно только
    # когда с неё ничего не запущено. TODO после первой загрузки: e2label.
    "/boot" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
    };

    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
      options = [ "nofail" "noauto" ];
    };
  };

  # ── Загрузчик ────────────────────────────────────────────
  # U-Boot на Pi понимает extlinux. Он же кладёт ядро и initrd в /boot,
  # то есть на SD. GRUB на этой платформе не при делах.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # ── Консоль ──────────────────────────────────────────────
  # ОБЯЗАТЕЛЬНО. Раньше эти параметры приходили из модуля sd-image-aarch64;
  # он убран — и вместе с ним пропали все console=. Без них ядро берёт
  # консоль из device tree (chosen/stdout-path), а это UART, который на
  # Pi 5 выключен в config.txt ([pi5] enable_uart=0). Итог: на HDMI не
  # появляется ни одной строки, экран остаётся на логотипе U-Boot.
  #
  # Порядок важен: основным /dev/console становится ПОСЛЕДНИЙ в списке,
  # поэтому tty0 стоит в конце — вывод пойдёт на HDMI. Ровно тот же набор
  # у рабочего live-образа, сверено построчно.
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=ttyAMA0,115200n8"
    "console=tty0"
  ];

  # Корень на NVMe, значит initrd обязан уметь его увидеть.
  # Без "nvme" система встанет на поиске корня.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "mmc_block"
  ];

  hardware.enableRedistributableFirmware = true;

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
