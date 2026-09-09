# hosts/rpinix — Raspberry Pi 5 (BCM2712), aarch64.
#
# ЭТАП 1: минимально загружаемая система. Sway, контейнеры и оптимизация
# батареи намеренно отключены — сначала добиваемся загрузки с NVMe,
# потом наращиваем по одному модулю. Разбор в docs/11-rpinix.md.
#
# ── ПОЧЕМУ НЕ U-BOOT ─────────────────────────────────────────
# Штатный sd-image-aarch64 грузится через U-Boot, и на SD-карте это
# работает. Но с NVMe — нет: в ubootRaspberryPiAarch64
#     boot_targets=mmc usb pxe dhcp
# NVMe в списке отсутствует, а блочного драйвера NVMe в сборке нет вовсе
# (нет строк nvme_scan, Identify, Namespace). Переопределять boot_targets
# бесполезно. Проверено разбором бинаря 2026-09-09, см. docs/13-*.md.
#
# Поэтому используем родную для Pi 5 схему — прошивка грузит ядро сама:
#   EEPROM (BOOT_ORDER=NVMe) → FIRMWARE (vfat) → config.txt
#      → kernel.img + initrd + bcm2712-rpi-5-b.dtb → корень (ext4)
# U-Boot и extlinux.conf в ней не участвуют.
{ config, pkgs, lib, ... }:

let
  # Прошивка Pi читает этот файл сама. Секции [pi5] не нужно: раздел
  # прошивки принадлежит только этой машине, всё кладём в [all].
  configTxt = pkgs.writeText "config.txt" ''
    [all]
    arm_64bit=1
    avoid_warnings=1
    disable_overscan=1

    # UART выключен намеренно. На части ревизий Pi 5 плавающий вход с UART
    # прерывает загрузку — апстрим по той же причине ставит enable_uart=0
    # в секции [pi5] (bugzilla.opensuse.org, баг 1251192).
    enable_uart=0

    # Ядро и initramfs лежат прямо здесь, на FAT-разделе.
    # "followkernel" = разместить initramfs сразу за ядром в памяти.
    kernel=kernel.img
    initramfs initrd followkernel
  '';

  # Должен быть ОДНОЙ строкой. kernelParams приходят из sd-image-aarch64:
  # console=tty0 стоит последним, а основным /dev/console становится именно
  # последний — значит вывод stage-2 попадёт на HDMI, а не в UART.
  cmdlineTxt = pkgs.writeText "cmdline.txt" ''
    init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}
  '';

  fw = "${pkgs.raspberrypifw}/share/raspberrypi/boot";
in
{
  imports = [
    ../../modules/common.nix
    # Включать по одному ПОСЛЕ первой успешной загрузки:
    # ../../modules/desktop-light.nix        # Sway на 7" DSI
    # ../../modules/battery-optimization.nix # питание (проверить tlp на ARM)
    # ../../modules/container.nix            # Podman
  ];

  networking.hostName = "rpinix";

  sdImage = {
    # ── Размер раздела прошивки ────────────────────────────
    # По умолчанию 30 МиБ — этого хватает для U-Boot, но здесь на FAT лежат
    # ядро (60 МБ) и initrd (28 МБ). Проверено: в 30 МиБ не влезает.
    firmwareSize = 512;

    # ── Метки и ID разделов ────────────────────────────────
    # По умолчанию ВСЕ образы NixOS получают FIRMWARE/NIXOS_SD и
    # firmwarePartitionID = 0x2178694e, из-за чего SD и NVMe неразличимы:
    # by-label указывает неизвестно на какой диск. Проверено на живой
    # машине 2026-09-09. Разводим явно, чтобы SD можно было не вынимать.
    firmwarePartitionID = "0x52504958";   # "RPIX" в ASCII
    firmwarePartitionName = "RPINIXFW";   # метка FAT, максимум 11 символов
    rootVolumeLabel = "RPINIX";

    # ── Содержимое раздела прошивки ────────────────────────
    # mkForce: sd-image-aarch64.nix задаёт это обычным присваиванием, и его
    # вариант кладёт u-boot.bin, который нам не подходит (см. шапку файла).
    populateFirmwareCommands = lib.mkForce ''
      # Прошивка Pi
      (cd ${fw} && cp bootcode.bin fixup*.dat start*.elf $NIX_BUILD_TOP/firmware/)

      # Device tree для Pi 5 и оверлеи (нужны позже для DSI)
      cp ${fw}/bcm2712-*.dtb firmware/
      cp -r ${fw}/overlays firmware/

      # Ядро и initramfs — их грузит сама прошивка, без U-Boot
      cp ${config.system.build.kernel}/${config.system.boot.loader.kernelFile} firmware/kernel.img
      cp ${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile} firmware/initrd

      cp ${configTxt} firmware/config.txt
      cp ${cmdlineTxt} firmware/cmdline.txt
    '';
  };

  # ВНИМАНИЕ: при такой схеме `nixos-rebuild switch` обновит систему и
  # /boot/extlinux на корне, но НЕ тронет ядро на FAT-разделе — машина
  # продолжит грузиться старым. Нужна служба синхронизации FAT при
  # активации. Не сделана намеренно: сначала добиваемся первой загрузки.
  # TODO: добавить после подтверждённой загрузки.

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
