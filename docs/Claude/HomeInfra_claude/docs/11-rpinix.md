---
tags: [хост, rpinix, pi5, установка, гайд]
---

# rpinix — установка NixOS на Raspberry Pi 5

> **Этот файл переписан 2026-09-09.** Предыдущая версия содержала неверные
> инструкции (`boot.loader.raspberryPi`, `hardware.raspberry-pi."5"`,
> generic-extlinux). Они не работают — почему, разобрано ниже в «Тупики».

## Почему Pi 5 не ставится «как обычный aarch64»

Три факта, проверенные по исходникам nixpkgs 26.05:

1. **`boot.loader.raspberryPi` удалён.** В `nixos/modules/rename.nix` от него
   осталась заглушка `mkRemovedOptionModule`, которая роняет вычисление.
2. **`ubootRaspberryPi5` не существует.** В nixpkgs есть `ubootRaspberryPi`,
   `…Pi2`, `…Pi3_32bit/64bit`, `…Pi4_32bit/64bit`, `…PiAarch64`, `…PiZero` —
   и всё. U-Boot для Pi 5 нет, значит extlinux-путь для Pi 5 не собирается.
3. **`sd-image-aarch64.nix` не знает про Pi 5.** В его `config.txt` есть секции
   `[pi3]`, `[pi02]`, `[pi4]`, `[cm4]`, но нет `[pi5]`, и `bcm2712-rpi-5-b.dtb`
   туда не копируется.

Плюс отдельная ловушка, которая стоила вечера:

**`nixos-install` не наполняет раздел прошивки.** Прошивка пишется только
сборщиком образа (`sdImage.populateFirmwareCommands`). Поэтому установка на
чистый NVMe даёт пустой FAT-раздел и `GPT: no bootable partitions` — сколько
ни переустанавливай.

Решение — флейк [`raspberry-pi-nix`](https://github.com/nix-community/raspberry-pi-nix):
в нём есть вендорное ядро под `bcm2712`, вендорная прошивка и сборка образа
с готовым разделом `FIRMWARE`.

## Как на самом деле грузится Pi 5

```
EEPROM (BOOT_ORDER) → раздел FIRMWARE (vfat) → config.txt → kernel.img → initrd → корень (ext4)
```

U-Boot и `extlinux.conf` в этой схеме **не участвуют**. У `raspberry-pi-nix`
опция `raspberry-pi-nix.uboot.enable` по умолчанию `false`, и в её описании
прямо сказано, что это нужный режим для «менее типичных схем, например
загрузки с NVMe». Ядро кладётся прямо в раздел прошивки.

Следствие: **корень обязан быть ext4**, `root=PARTUUID=<id>-02`. btrfs здесь
не подходит.

## Конфиг

`hosts/rpinix/default.nix` — этап 1, минимально загружаемая система:

```nix
imports = [ ../../modules/common.nix ];
raspberry-pi-nix.board = "bcm2712";   # Pi 5. bcm2711 — это Pi 4
system.stateVersion = "26.05";
```

Чего в нём намеренно **нет**:

- `hardware-configuration.nix` и `fileSystems` — разметку описывает модуль `sd-image`
- `boot.kernelPackages` — ядро выбирает `raspberry-pi-nix`
- `boot.loader.*` — загрузчиком управляет тот же модуль
- Sway, контейнеры, оптимизация батареи — подключаются по одному ПОСЛЕ первой загрузки

Во `flake.nix` модули подключены через `extraModules`:

```nix
rpinix = {
  system = "aarch64-linux";
  home = null;
  extraModules = [
    inputs.raspberry-pi-nix.nixosModules.raspberry-pi
    inputs.raspberry-pi-nix.nixosModules.sd-image
  ];
};
```

**`raspberry-pi-nix` подключён без `inputs.nixpkgs.follows`.** Это не забывчивость:
у флейка свой пин nixpkgs, под который CI собрал ядра в `nix-community.cachix.org`.
Переопределишь nixpkgs — промахнёшься мимо кэша и будешь компилировать ядро
на самой малине несколько часов.

## Порядок установки

### 1. На kitjet: закоммитить и запушить

```bash
cd ~/nixos
git add -A
git commit -m "rpinix: Pi 5 через raspberry-pi-nix"
git push
```

### 2. Проверить вычисление (не сборку)

```bash
nix eval --raw .#nixosConfigurations.rpinix.config.system.build.sdImage.drvPath
```

Должен вернуться путь `.drv`. Это ловит конфликты опций за секунды вместо часов
сборки — в отличие от `nix flake show`, который модули не разворачивает.

### 3. На Pi (загруженной с SD): собрать образ

Ключ кэша взять на https://nix-community.cachix.org — там напечатана готовая
строка `extra-trusted-public-keys`. По памяти его вписывать нельзя: это ключ
проверки подписи бинарников.

```bash
cd /tmp/nixos && git pull

nix build .#nixosConfigurations.rpinix.config.system.build.sdImage \
  --option extra-substituters https://nix-community.cachix.org \
  --option extra-trusted-public-keys '<строка с сайта кэша>'
```

Без кэша соберётся тоже, но вендорное ядро компилируется на Pi очень долго.

### 4. Записать образ на NVMe

Образ сжат (`sdImage.compressImage` по умолчанию включён):

```bash
ls result/sd-image/                       # nixos-sd-image-*.img.zst
zstdcat result/sd-image/*.img.zst | dd of=/dev/nvme0n1 bs=4M status=progress
sync
```

Разметку руками делать **не нужно** — она внутри образа (msdos, FIRMWARE + NIXOS_SD).

### 5. Вынуть SD и загрузиться

Корень растянется на все 238 ГБ автоматически: за это отвечает
`sdImage.expandOnBoot` и сервис `expand-root-partition`.

Вход: `gadjet` / `1414` (задано `users.users.gadjet.initialPassword`).
**Сменить сразу:** `passwd`.

### 6. Дальше — по одному модулю

После подтверждённой загрузки раскомментировать в `hosts/rpinix/default.nix`
по одному импорту, каждый раз пересобирая:

- `modules/desktop-light.nix` — Sway на 7" DSI
- `modules/battery-optimization.nix` — питание
- `modules/container.nix` — Podman

## Тупики (чтобы не повторять)

| Что пробовали | Чем кончилось |
| --- | --- |
| `boot.loader.raspberryPi.version = 5` | опция удалена из nixpkgs, вычисление падает |
| `hardware.raspberry-pi."5"` | опции нет в nixpkgs, она из `nixos-hardware` |
| generic sd-image + `nixos-install` на NVMe | раздел прошивки пуст → `GPT: no bootable partitions` |
| корень btrfs на NVMe | Pi-схема требует ext4 и `root=PARTUUID=…-02` |
| разметка руками (`parted` + `mkfs.fat`) | не помогает: дело не в разметке, а в содержимом FAT |
| `root=/dev/nvme0n1` в `kernelParams` | выдумано, к делу отношения не имеет |

Общий вывод: `nix flake show` показывает, что конфигурация *объявлена*, но не
разворачивает модули. Проверять надо `nix eval …config.system.build.<цель>.drvPath`.

## Открытые вопросы

- Последний коммит `raspberry-pi-nix` — март 2025, его nixpkgs запинён на январь 2025.
  С 26.05 он сходится при вычислении, но это заметный отрыв. Следить при обновлениях.
- `modules/battery-optimization.nix` содержит `services.tlp` и `thermald` — обе вещи
  x86-ориентированные. `thermald` уже отключён для aarch64; `tlp` на ARM надо проверить
  отдельно, до включения модуля.
- `networking.wireless.iwd` + NetworkManager требуют
  `networking.networkmanager.wifi.backend = "iwd"`, иначе конфликтуют. Сейчас в
  минимальном конфиге iwd не участвует.
- Роль машины: 7" DSI + батареи + NVMe — портативное устройство, см. [[12-rpinix-portable]].

[[00-Проект]] · [[10-kitjet]] · [[12-rpinix-portable]] · [[30-Грабли]]
