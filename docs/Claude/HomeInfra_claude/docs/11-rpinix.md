---
tags: [хост, rpinix, pi5, установка, гайд]
---

# rpinix — установка NixOS на Raspberry Pi 5

> **Переписан 2026-09-09 (второй раз).** Предыдущая версия вела через флейк
> `raspberry-pi-nix`. Это оказалось лишним: Pi 5 поддержан в nixpkgs штатно,
> просто не в стабильной ветке. Разбор — [[13-rpinix-диагностика-загрузки]].

## Главное в одну строку

**Pi 5 работает на стандартном `sd-image-aarch64`, но только из
`nixpkgs-unstable`. В ветке 26.05 поддержки нет.**

Сравнение `nixos/modules/installer/sd-card/sd-image-aarch64.nix`:

| | nixos-26.05 | nixos-unstable |
|---|---|---|
| секции `[pi5]`, `[cm5]` | нет | **есть** |
| `bcm2712-*.dtb` | не копируются | **все 7** |
| U-Boot | `u-boot-rpi3.bin`, `u-boot-rpi4.bin` | **`ubootRaspberryPiAarch64` → `u-boot.bin`** |

Обновление 26.05 не помогает — проверено.

## Как грузится Pi 5

```
EEPROM (BOOT_ORDER) → раздел FIRMWARE (vfat) → config.txt → u-boot.bin
   → U-Boot читает /boot/extlinux/extlinux.conf на корне (ext4)
   → ядро + initrd + dtb
```

Корень обязан быть **ext4**: U-Boot читает с него `extlinux.conf`.

## Конфиг

Хост собирается из другой ветки, чем остальные. Во `flake.nix` это сделано так:

```nix
mkHost = name: cfg:
  let np = cfg.nixpkgs or nixpkgs;   # не указал — берётся основная
  in np.lib.nixosSystem { ... };
```

```nix
rpinix = {
  system = "aarch64-linux";
  home = null;                       # пока без home-manager
  nixpkgs = inputs.nixpkgs-unstable; # ТОЛЬКО здесь есть Pi 5
  extraModules = [
    "${inputs.nixpkgs-unstable}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
  ];
};
```

`hosts/rpinix/default.nix` — этап 1, минимально загружаемая система. Чего в нём
намеренно **нет**: `hardware-configuration.nix`, `fileSystems`,
`boot.kernelPackages`, `boot.loader.*` — всё это задаёт модуль `sd-image`.

### Метки разделов обязательно свои

По умолчанию **любой** NixOS sd-image получает `FIRMWARE`/`NIXOS_SD` и
`firmwarePartitionID = 0x2178694e`. Поэтому SD-карта и NVMe становятся
неразличимы, а `root=` и `by-label` указывают неизвестно куда:

```nix
sdImage = {
  firmwarePartitionID = "0x52504958";   # не 0x2178694e
  firmwarePartitionName = "RPINIXFW";   # метка FAT, максимум 11 символов
  rootVolumeLabel = "RPINIX";           # вместо NIXOS_SD
};
```

С этим SD можно держать вставленной.

## Порядок установки

### 1. Проверить вычисление (секунды вместо часов)

```bash
cd ~/nixos
nix eval --raw .#nixosConfigurations.rpinix.config.system.build.sdImage.drvPath
```

Должен вернуться путь `.drv`. Ловит конфликты опций мгновенно — в отличие от
`nix flake show`, который модули не разворачивает.

### 2. Доставить конфиг на Pi

Если git на Pi нет (в live-системе с SD его нет), каталог без `.git` тоже
годится: nix воспримет его как path-флейк.

```bash
cd ~/nixos
tar -c --exclude=.git --exclude=docs . | ssh nixos@<ip> \
  'rm -rf /tmp/nixos-new && mkdir -p /tmp/nixos-new && tar -x -C /tmp/nixos-new'
```

### 3. Собрать образ на Pi

Cachix больше не нужен — всё берётся из официального `cache.nixos.org`.
Команда **одной строкой**: обратные слэши при вставке рвутся, и `nix` принимает
`build` за имя флейка (`error: cannot find flake 'flake:build'`).

```bash
cd /tmp/nixos-new && nix --extra-experimental-features 'nix-command flakes' build .#nixosConfigurations.rpinix.config.system.build.sdImage
```

`--extra-experimental-features` обязателен: в live-системе флейки выключены.

Реально занимает минуты — компилируется только образ, пакеты приходят готовыми.

### 4. Записать на NVMe

```bash
for m in /mnt/nvme /mnt/fw; do while mountpoint -q $m; do sudo umount $m; done; done
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/nvme0n1 bs=4M status=progress conv=fsync
sync
```

`sudo` нужен именно на `dd`. Разметку руками делать не надо — она внутри образа.

### 5. Проверить перед перезагрузкой

```bash
lsblk -o NAME,SIZE,LABEL,PARTUUID,FSTYPE
```

Ожидается `RPINIXFW`/`RPINIX` на nvme и `FIRMWARE`/`NIXOS_SD` на SD — разные.

```bash
sudo mount /dev/nvme0n1p1 /mnt/fw && ls /mnt/fw | grep -E 'u-boot|bcm2712-rpi-5'
```

Должны быть `u-boot.bin` и `bcm2712-rpi-5-b.dtb`.

### 6. Загрузиться

**Вынуть SD** — иначе EEPROM по BOOT_ORDER уйдёт грузиться с неё.

Корень растянется на все 238 ГБ сам (`sdImage.expandOnBoot`).
Вход: `gadjet` / `1414`. **Сменить сразу:** `passwd`.

### 7. Дальше — по одному модулю

Раскомментировать в `hosts/rpinix/default.nix` по одному, пересобирая каждый раз:

- `modules/desktop-light.nix` — Sway на 7" DSI
- `modules/battery-optimization.nix` — питание (проверить `tlp` на ARM)
- `modules/container.nix` — Podman

## Тупики (чтобы не повторять)

| Что пробовали | Чем кончилось |
| --- | --- |
| `boot.loader.raspberryPi.version = 5` | опция удалена из nixpkgs, вычисление падает |
| `hardware.raspberry-pi."5"` | опции нет в nixpkgs, она из `nixos-hardware` |
| sd-image из **26.05** + `nixos-install` на NVMe | прошивка пуста → `GPT: no bootable partitions` |
| корень btrfs на NVMe | нужен ext4: с него U-Boot читает `extlinux.conf` |
| разметка руками (`parted` + `mkfs.fat`) | дело не в разметке, а в содержимом FAT |
| `root=/dev/nvme0n1` в `kernelParams` | выдумано, к делу отношения не имеет |
| флейк `raspberry-pi-nix` | грузился до switch-root и молча вставал; вендорное ядро 6.6.51, пин nixpkgs на январь 2025, отдельный кэш, баг `tpm-crb` |

`nix flake show` показывает, что конфигурация *объявлена*, но модули не
разворачивает. Проверять надо `nix eval …config.system.build.<цель>.drvPath`.

## Исторические ошибки сборки

Обе относятся к `raspberry-pi-nix` и после перехода на штатный образ
неактуальны. Оставлено на случай возврата.

### `modprobe: FATAL: Module tpm-crb not found`

`nixos/modules/system/boot/systemd/tpm2.nix` добавляет в initrd `tpm-tis` и
`tpm-crb` для всего, кроме riscv64 и armv7. aarch64 под исключение не попадает,
а вендорное ядро Pi этот модуль не собирает. Лечилось
`boot.initrd.systemd.tpm2.enable = false`. На mainline-ядре 6.18 не возникает.

### `error: cannot find flake 'flake:build'`

Не ошибка nix, а порванная при вставке строка: слэши потерялись, `build` уехал
в аргументы. Команду сборки копировать одной строкой.

[[00-Проект]] · [[10-kitjet]] · [[12-rpinix-portable]] · [[13-rpinix-диагностика-загрузки]] · [[30-Грабли]]
