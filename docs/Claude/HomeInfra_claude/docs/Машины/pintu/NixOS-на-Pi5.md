---
tags: [pintu, pi5, nixos, архив, dsi, гайд]
---

# NixOS на Raspberry Pi 5 — рабочий рецепт и почему отложено

> **Статус: отложено** (2026-09-10). NixOS на Pi 5 **работает** — корень на
> NVMe, загрузка с SD, ядро 6.18.49 mainline. Но **DSI-дисплей на mainline
> невозможен**, а для портативного сценария это блокер. Поэтому машина сейчас
> на Ubuntu — см. [[pintu]].
>
> Здесь собрано всё, чтобы вернуться без повторной отладки: рабочая схема,
> почему нет DSI, условия возврата и уроки. Полная история отладки —
> [[Отладка-загрузки-NixOS]].
>
> Конфиг сохранён в репозитории: `hosts/rpinix/` (старое имя машины).

## Когда возвращаться

- в `vc4.ko` появится `brcm,bcm2712-dsi` — mainline научился DSI на Pi 5, **или**
- в nixpkgs появится `linux_rpi5`, **или**
- будет желание возиться с вендорным ядром через `raspberry-pi-nix` —
  план и риски в разделе про DSI ниже.

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
  Разбор и варианты — в разделе про DSI ниже.
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


## DSI-дисплей: не работает на mainline-ядре

### Что показала проверка

Машина загружена, ядро 6.18.49 mainline (NixOS 26.11). Состояние подсистемы
вывода:

```
$ ls /sys/class/drm/
card1  card1-HDMI-A-1  card1-HDMI-A-2  card1-Writeback-1  card1-Writeback-2

card1-HDMI-A-1     connected
card1-HDMI-A-2     disconnected
```

Коннектора DSI **нет вообще**. Драйвер `vc4` при этом загружен и работает —
HDMI функционирует.

Причина в device tree. В DTB для `bcm2712` из дерева mainline-ядра:

```bash
dtc -I dtb -O dts .../broadcom/bcm2712-rpi-5-b.dtb | grep -ic 'dsi\|mipi'
# 0
```

**Ноль упоминаний.** Узла DSI-хоста в описании железа нет, поэтому привязывать
драйвер панели не к чему. Драйверов панелей в ядре при этом полно
(`/lib/modules/*/kernel/drivers/gpu/drm/panel/`, десятки `panel-*.ko`), но они
бесполезны без узла DSI.

Это не вопрос настройки и не лечится оверлеем: нужно, чтобы контроллер DSI
для bcm2712 появился в mainline. У Pi 4 (`bcm2711`) он есть, у Pi 5 — пока нет.

### Доказательство на уровне драйвера

DT — только следствие. Сам модуль `vc4` не содержит кода DSI для bcm2712.
Строки `compatible` внутри `vc4.ko`:

```bash
tr -c '[:print:]' '\n' < vc4.ko | grep -oE 'brcm,bcm[0-9]+-[a-z0-9-]+' | sort -u
```

| SoC | DSI |
|---|---|
| `bcm2835` (Pi 1-3) | `dsi0`, `dsi1` |
| `bcm2711` (Pi 4) | `dsi1` |
| **`bcm2712` (Pi 5)** | **отсутствует** |

Для bcm2712 драйвер знает `hdmi0`, `hdmi1`, `hvs`, `mop`, `moplet`,
`pixelvalve0/1`, `vc6` — и всё. Оверлеем это не обходится: включать нечего.

Вдобавок в nixpkgs нет вендорного ядра для Pi 5 — только `linux_rpi1`…`linux_rpi4`.

### Дисплей у нас

Официальный **Raspberry Pi 7" Touchscreen** (800x480), подключён.
Нужен оверлей `vc4-kms-dsi-7inch`, тач — `rpi-ft5406` по I2C.
Оба существуют только в вендорном ядре Raspberry Pi.

### Варианты

| Путь | Что даёт | Чего стоит |
|---|---|---|
| **Ждать mainline** | ничего делать не надо | сроки неизвестны |
| **Вендорное ядро Raspberry Pi** | DSI работает, есть `vc4-kms-dsi-*` оверлеи | ядро 6.6/6.12 вместо 6.18; отдельный кэш; ранее ловили баг `tpm-crb` |
| **HDMI вместо DSI** | работает сейчас | не портативно |

Вендорное ядро — реальный вариант **именно теперь**: раньше мы отказались от
`raspberry-pi-nix` из-за загрузки, а сейчас грузимся штатным U-Boot с SD, и
ядро можно подменить независимо от схемы загрузки. Но проверять надо отдельно
и не ломая рабочую конфигурацию.

### План, если браться за вендорное ядро

Делать отдельной задачей и не ломая рабочую систему:

1. Вернуть `raspberry-pi-nix` в inputs **только ради ядра** —
   его модули загрузки (`raspberry-pi`, `sd-image`) НЕ подключать:
   схема загрузки у нас своя и работает.
2. `boot.kernelPackages` — вендорное ядро bcm2712.
3. DTB брать вендорный, вместе с каталогом `overlays`, и добавить
   `vc4-kms-dsi-7inch`. Проверить, что PCIe при этом не отвалился:
   у вендорного DTB внешний разъём включается иначе (`dtparam=pciex1`
   применяет прошивка), а мы грузим DTB через `FDTDIR` мимо неё.
4. Откат: `generic-extlinux-compatible` держит прошлые поколения
   в меню U-Boot — старое ядро выбирается с клавиатуры на HDMI.

Риски: ядро 6.6/6.12 вместо 6.18; свой пин nixpkgs у флейка;
именно на нём мы ловили баг `tpm-crb`. PCIe придётся перепроверять.

## Сенсорный ввод

Пока нет DSI, проверять нечего. После появления вывода: тач у официальных
панелей идёт по I2C отдельным устройством, в NixOS нужен
`services.libinput.enable = true`, для калибровки — `libinput measure`.


## Чему научила вся цепочка

1. **Сначала консоль, потом всё остальное.** Половина времени ушла на
   загадочные «зависания», которые были обычными ошибками с невидимым выводом.
   Первым делом надо убеждаться, что `console=` настроен и лог виден.
2. **Фото экрана — самый дешёвый источник истины.** Каждое из трёх фото
   сокращало поиск на порядок сильнее, чем любые рассуждения.
3. **Проверять результат, а не факт выполнения.** Оверлей «применился»
   без ошибок, но не применился. Сборка прошла — DTB остался прежним.
4. **Сравнение с заведомо рабочим — сильнейший инструмент.** Живая
   live-система на той же карте дала ответ про `console=` за одну команду
   `diff`, после того как я долго гадал о размерах ядра и памяти.


[[00-Проект]] · [[pintu]] · [[Отладка-загрузки-NixOS]] · [[Грабли]]
