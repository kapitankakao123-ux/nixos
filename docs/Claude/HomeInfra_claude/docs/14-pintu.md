---
tags: [хост, pintu, pi5, ubuntu, установка, гайд]
---

# pintu — Raspberry Pi 5 на Ubuntu

> **Решение 2026-09-10.** NixOS на Pi 5 работает, но без DSI (в mainline
> нет кода DSI для bcm2712, см. [[12-rpinix-portable]]). Для портативного
> сценария это блокер, поэтому Pi 5 пока на Ubuntu. kitjet и gadnix — NixOS.
> Рабочая схема NixOS сохранена в [[11-rpinix]] на случай возврата.

## Почему Ubuntu снимает оба наших тупика

- **DSI.** Ядро Ubuntu для Raspberry Pi собрано с поддержкой Pi 5 целиком,
  включая DSI и оверлеи `vc4-kms-dsi-*`. Официальный 7" дисплей определяется
  прошивкой сам (`display_auto_detect=1`).
- **Загрузка с NVMe.** Ubuntu грузится прошивкой Pi напрямую, без U-Boot.
  Поэтому ограничение `boot_targets=mmc usb pxe dhcp` здесь не действует.

## Образ

Из официального каталога Raspberry Pi — того же, что использует rpi-imager
(`https://downloads.raspberrypi.com/os_list_imagingutility_v4.json`):

| | |
|---|---|
| Версия | Ubuntu Server 26.04.1 (resolute) |
| Файл | `ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz` |
| Размер | 1457 МБ сжатый, 4.6 ГиБ распакованный |
| sha256 | `d59ef9c6e85b906995501f166d00726ab80b59be7b65cdeac0fa31b996053e13` |

Server, а не Desktop: под контейнеры он легче. Рабочий стол при желании
добавляется потом — `sudo apt install ubuntu-desktop-minimal`. Обратное
(выпилить GUI из Desktop-образа) заметно грязнее.

## Запись на SD

### rpi-imager под niri не работает

`nix run nixpkgs#rpi-imager` (2.0.9) грузит интерфейс, скачивает каталог ОС —
и **молча завершается без окна**, без падения и без ошибки в журнале. Под
этим Wayland-композитором Qt-сборка не показывает окно. Разбираться не стали:
то же самое делается напрямую.

Попутно он предупреждает `Not running with elevated privileges - device
access may fail` — даже с окном без прав на запись карту бы не прошил.

### Напрямую: скачать, проверить, записать

```bash
cd ~/Downloads
curl -LO http://cdimage.ubuntu.com/releases/resolute/release/ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz
echo "d59ef9c6e85b906995501f166d00726ab80b59be7b65cdeac0fa31b996053e13  ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz" | sha256sum -c

lsblk -o NAME,SIZE,LABEL,TRAN,MODEL      # ОБЯЗАТЕЛЬНО убедиться, что sdX — это карта
xzcat ubuntu-26.04.1-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Ловушка при ожидании: `pgrep -f "curl.*ubuntu…+raspi…"` не находит процесс —
`+` в имени файла это спецсимвол регулярки. Проверять `pgrep -x curl`.

### Настройка первой загрузки — cloud-init

То, что rpi-imager делает кнопкой «кастомизация», — это запись в `user-data`
на разделе `system-boot`. Пишем сами:

```yaml
#cloud-config
hostname: pintu
manage_etc_hosts: true
timezone: Europe/Moscow

users:
  - name: gadjet
    groups: [adm, sudo, dialout, plugdev, video]
    shell: /bin/bash
    lock_passwd: false
    passwd: <хеш>          # mkpasswd -m sha-512 <пароль>
    sudo: ALL=(ALL) ALL

chpasswd:
  expire: false            # не требовать смену пароля при первом входе

ssh_pwauth: true           # по паролю, пока нет ключа
```

Блок `users:` **заменяет** стандартного пользователя `ubuntu` с принудительной
сменой пароля. Оригинал сохранён рядом как `user-data.orig`.

`network-config` стандартный — DHCP по кабелю на `eth0`, трогать не надо.

Проверить синтаксис до загрузки:

```bash
yq '.hostname, .users[0].name, .ssh_pwauth' /run/media/$USER/system-boot/user-data
```

## Перенос на NVMe (выполнено 2026-09-10)

Проверено по шагам на живой машине.

### 1. Скачать образ прямо на Pi

По кабелю быстрее, чем гнать 1.5 ГБ с kitjet по Wi-Fi:

```bash
cd /tmp
curl -LO http://cdimage.ubuntu.com/releases/resolute/release/ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz
echo "d59ef9c6e85b906995501f166d00726ab80b59be7b65cdeac0fa31b996053e13  ubuntu-26.04.1-preinstalled-server-arm64+raspi.img.xz" | sha256sum -c
```

### 2. Записать на NVMe

```bash
sudo sh -c "xzcat /tmp/ubuntu-*.img.xz | dd of=/dev/nvme0n1 bs=4M conv=fsync status=progress"
```

Весь конвейер — внутри `sh -c`. Если писать `xzcat … | sudo dd`, а пароль
подавать через `sudo -S`, то stdin занят потоком образа и пароль не дойдёт.

### 3. Положить user-data на NVMe

```bash
sudo mount /dev/nvme0n1p1 /mnt
sudo cp /mnt/user-data /mnt/user-data.orig
sudo cp <наш user-data> /mnt/user-data     # hostname: pintu
sudo umount /mnt
```

### 4. EEPROM: NVMe первым

Было `BOOT_ORDER=0xf461` — читается справа налево: **1 (SD) → 6 (NVMe)** →
4 (USB) → f (повтор). Поэтому с картой в слоте Pi всегда уходила в SD.

```bash
sudo rpi-eeprom-config > /tmp/eeprom.conf
sed -i "s/^BOOT_ORDER=.*/BOOT_ORDER=0xf416/" /tmp/eeprom.conf
sudo rpi-eeprom-config --apply /tmp/eeprom.conf     # ждём VERIFY: SUCCESS
```

`PCIE_PROBE=1` **не понадобился**: EEPROM видит NVMe и без него — это
доказано ещё попыткой с NixOS, когда Pi сама загрузилась с NVMe.

### 5. ВЫНУТЬ SD — обязательно

SD и NVMe записаны из одного образа, поэтому совпадают **и метки, и PARTUUID**:

```
mmcblk0p1  system-boot  c1b80844-01      nvme0n1p1  system-boot  c1b80844-01
mmcblk0p2  writable     c1b80844-02      nvme0n1p2  writable     c1b80844-02
```

А корень Ubuntu ищет по метке:

```
cmdline:  root=LABEL=writable
fstab:    LABEL=writable  /   и   LABEL=system-boot  /boot/firmware
```

С двумя дисками загрузчик возьмёт NVMe, а корень может подцепиться с SD.
Та же ловушка, что была с `NIXOS_SD` у NixOS.

Загрузочные файлы в 26.04 лежат в `/boot/firmware/current/` (схема A/B),
а не в корне раздела — `cmdline.txt` искать там.

### 6. Загрузиться

Корень растянется на весь диск при первой загрузке сам (cloud-init).

## Контейнеры: LXC на Ubuntu — да

На Ubuntu LXC — родная технология: Canonical её и развивает. Варианты:

- **Incus** — общественный форк LXD, есть в репозиториях Ubuntu:
  `sudo apt install incus`. Рекомендуется: без snap, активно развивается.
- **LXD** — вариант от Canonical, ставится через snap: `sudo snap install lxd`.

Оба работают на arm64, то есть на Pi 5.

**Правило «LXC не использовать» из `CLAUDE.md` к Ubuntu не относится.** Оно
было про NixOS: там `virtualisation.lxc` императивный — контейнеры создаются
руками, во flake не описываются, откатов нет. На Ubuntu вся система и так
императивная, и Incus/LXD — штатный инструмент, а не чужеродная обвязка.

На Pi 5 только **arm64-образы**: x86 не запустятся (как и раньше с KVM).

[[00-Проект]] · [[11-rpinix]] · [[12-rpinix-portable]] · [[30-Грабли]]
