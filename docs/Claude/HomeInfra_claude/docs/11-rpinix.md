---
tags: [хост, rpinix, pi5, установка, гайд]
---

# rpinix — NixOS на Raspberry Pi 5

> **Статус: РАБОТАЕТ** (2026-09-10). Корень на NVMe, загрузка с SD,
> ядро 6.18.49 mainline, NixOS 26.11. История отладки — [[13-rpinix-диагностика-загрузки]].

## Итоговая схема

```
EEPROM → SD p1 (vfat, FIRMWARE) → config.txt → u-boot.bin
       → U-Boot читает /extlinux/extlinux.conf на SD p2 (ext4)
       → ядро + initrd + DTB оттуда же
       → initrd поднимает PCIe, находит корень на NVMe
```

| Раздел | Метка | Роль |
|---|---|---|
| `mmcblk0p1` (30 МБ, vfat) | `FIRMWARE` | `/boot/firmware` — прошивка Pi + `u-boot.bin` |
| `mmcblk0p2` (58 ГБ, ext4) | `NIXOS_SD` | `/boot` — extlinux, ядро, initrd, DTB |
| `nvme0n1p1` (238 ГБ, ext4) | `RPINIXROOT` | `/` — вся система |

**SD обязана оставаться в слоте.** U-Boot из nixpkgs не умеет NVMe, поэтому
ядро лежит на карте. Записей на `/boot` почти нет — износ несущественный.

Плюс схемы: `nixos-rebuild` работает штатно, ядро и initrd на `/boot`
обновляет сам `generic-extlinux-compatible`. Никакой ручной синхронизации.

## Три вещи, без которых не грузится

Каждая ловила нас отдельно, порядок важен.

### 1. Ветка nixpkgs — только unstable

В `nixos-26.05` нет поддержки Pi 5 в `sd-image-aarch64.nix`: ни секций
`[pi5]`/`[cm5]`, ни `bcm2712-*.dtb`, ни общего `u-boot.bin`. Обновление 26.05
не помогает. Во `flake.nix` хост берёт свою ветку:

```nix
mkHost = name: cfg:
  let np = cfg.nixpkgs or nixpkgs;   # не указал — берётся основная
  in np.lib.nixosSystem { ... };
```

```nix
rpinix = { system = "aarch64-linux"; home = null; nixpkgs = inputs.nixpkgs-unstable; };
```

### 2. Параметры console

Без них ядро берёт консоль из device tree (`chosen/stdout-path`), а это UART,
выключенный на Pi 5 (`[pi5] enable_uart=0`). На HDMI не появляется **ни одной
строки** — выглядит как зависание U-Boot.

```nix
boot.kernelParams = [ "console=ttyS0,115200n8" "console=ttyAMA0,115200n8" "console=tty0" ];
boot.consoleLogLevel = 7;
```

`tty0` **последним**: основным `/dev/console` становится последний в списке.

### 3. PCIe — две независимые правки

Драйвер контроллера PCIe у Broadcom — **модуль**, не встроенный. Проверка:

```bash
grep -c brcm_pcie <ядро>/System.map     # 0  → модуль
grep -c dw_pcie   <ядро>/System.map     # 129 → встроен
```

Поэтому внутренний RP1 (USB, Ethernet) работает, а внешний разъём — нет.

```nix
boot.initrd.kernelModules = [ "pcie_brcmstb" ];
```

И вдобавок в mainline-DTB внешний разъём выключен:

```
pcie@1000100000  status = "disabled"   ← сюда воткнут NVMe
pcie@1000110000  status = "okay"
pcie@1000120000  status = "okay"       ← RP1
```

На Raspberry Pi OS его включает `dtparam=pciex1`, но это применяет **прошивка**
к своему DTB, а U-Boot берёт наш — из дерева ядра через `FDTDIR`. Включаем сами:

```nix
hardware.deviceTree = {
  enable = true;
  filter = "*bcm2712-rpi-5-b.dtb";
  overlays = [{
    name = "pcie-external-enable";
    dtsText = ''
      /dts-v1/;
      /plugin/;
      / {
        compatible = "brcm,bcm2712";
        fragment@0 {
          target-path = "/axi/pcie@1000100000";
          __overlay__ { status = "okay"; };
        };
      };
    '';
  }];
};
```

**`compatible` в корне оверлея обязателен.** `apply_overlays.py` из nixpkgs
молча пропускает оверлей, если корневой `compatible` не пересекается с
`compatible` целевого DTB. Успешная сборка **не значит**, что оверлей применён.

## Установка с нуля

### 1. Подготовить диски (из live-системы с SD)

```bash
sudo wipefs -a /dev/nvme0n1
sudo parted -s /dev/nvme0n1 mklabel gpt mkpart primary ext4 1MiB 100%
sudo partprobe /dev/nvme0n1
sudo mkfs.ext4 -L RPINIXROOT -F /dev/nvme0n1p1
```

SD берётся готовая — записанный штатный `sd-image-aarch64` из unstable.
Её раздел прошивки уже содержит `u-boot.bin` и все `bcm2712-*.dtb`.

### 2. Доставить конфиг

Git на live-системе нет. Каталог без `.git` nix принимает как path-флейк:

```bash
cd ~/nixos
tar -c --exclude=.git --exclude=docs . | ssh nixos@<ip> \
  'rm -rf /tmp/nixos-new && mkdir -p /tmp/nixos-new && tar -x -C /tmp/nixos-new'
```

### 3. Смонтировать и установить

`/boot` — это корень раздела SD, поэтому bind-монтируем `/` живой системы:

```bash
sudo mount /dev/disk/by-label/RPINIXROOT /mnt
sudo mkdir -p /mnt/boot
sudo mount --bind / /mnt/boot
sudo NIX_CONFIG="experimental-features = nix-command flakes" \
  nixos-install --flake /tmp/nixos-new#rpinix --root /mnt --no-root-password
```

Установщик кладёт `extlinux.conf` в **корень** раздела SD (`/extlinux/`).
Конфиг live-системы остаётся уровнем ниже (`/boot/extlinux/`) — U-Boot ищет
`/extlinux/` раньше, поэтому выигрывает наш, а live остаётся запасным.

### 4. Проверить ДО перезагрузки

```bash
# оверлей реально применён?
fdtget /mnt/boot/nixos/*device-tree-overlays/broadcom/bcm2712-rpi-5-b.dtb \
  /axi/pcie@1000100000 status          # ждём: okay

# модуль контроллера в initrd?
zstdcat /mnt/boot/nixos/*initrd | cpio -t | grep pcie-brcmstb

# console в cmdline?
grep -o 'console=[^ ]*' /mnt/boot/extlinux/extlinux.conf
```

### 5. Загрузиться

SD и NVMe обе на месте. Вход: `gadjet` / `1414`.

## Откат к live-системе

Если наш конфиг не грузится, а нужен доступ — вставить SD в другую машину и:

```bash
sudo mv /run/media/$USER/NIXOS_SD/extlinux /run/media/$USER/NIXOS_SD/extlinux.off
```

U-Boot не найдёт `/extlinux/`, спустится к `/boot/extlinux/` и загрузит live.
Вернуть — переименовать обратно.

## Что не работает

- **DSI-дисплей.** Драйвер `vc4` не содержит DSI для bcm2712 (есть для bcm2835 и bcm2711), поэтому и узла в DT нет.
  Разбор и варианты — [[12-rpinix-portable]].
- **`nixos-rebuild` требует SD в слоте** — иначе `/boot` не смонтируется.

## Тупики (чтобы не повторять)

| Что пробовали | Чем кончилось |
| --- | --- |
| `boot.loader.raspberryPi.version = 5` | опция удалена из nixpkgs |
| `hardware.raspberry-pi."5"` | опции нет в nixpkgs, она из `nixos-hardware` |
| sd-image из **26.05** | нет поддержки Pi 5, см. выше |
| `nixos-install` на чистый NVMe | раздел прошивки пуст → `GPT: no bootable partitions` |
| корень btrfs | нужен ext4 |
| флейк `raspberry-pi-nix` | вендорное ядро 6.6.51, пин nixpkgs на январь 2025, свой кэш, баг `tpm-crb`; вставал на switch-root |
| загрузка ядра прошивкой напрямую, без U-Boot | чёрный экран, без UART не диагностируется |
| **загрузка с NVMe через U-Boot** | `boot_targets=mmc usb pxe dhcp`, драйвера NVMe в сборке нет |

`nix flake show` показывает, что конфигурация *объявлена*, но модули не
разворачивает. Проверять надо `nix eval …config.system.build.<цель>.drvPath`.

[[00-Проект]] · [[10-kitjet]] · [[12-rpinix-portable]] · [[13-rpinix-диагностика-загрузки]] · [[30-Грабли]]
