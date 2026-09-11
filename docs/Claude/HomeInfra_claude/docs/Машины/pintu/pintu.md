---
tags: [хост, pintu, pi5, ubuntu, установка, гайд]
---

# pintu — Raspberry Pi 5 на Ubuntu

> **Статус: РАБОТАЕТ** (2026-09-10). Ubuntu 26.04.1 на NVMe, GNOME на 7" DSI,
> Firefox, Incus. Установка и все ловушки — ниже.
>
> **Решение 2026-09-10.** NixOS на Pi 5 работает, но без DSI (в mainline
> нет кода DSI для bcm2712, см. [[NixOS-на-Pi5]]). Для портативного
> сценария это блокер, поэтому Pi 5 пока на Ubuntu. kitjet и deskjet — NixOS.
> Рабочая схема NixOS сохранена в [[NixOS-на-Pi5]] на случай возврата.

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

## Ловушка: пустые индексы apt в образе

Первая попытка `apt install ubuntu-desktop-minimal` упала на зависимостях:

```
gstreamer1.0-packagekit Depends packagekit (= 1.3.4-3)
  but none of the choices are installable
```

Выглядело как рассинхрон архива: установлен `packagekit 1.3.4-3ubuntu1.2`,
а apt видит только `1.3.4-3` из `resolute/main`. Следом тем же упал
`python3-distupgrade`. **Обе версии при этом есть на сервере в
`resolute-updates`** — проверено запросом к зеркалу напрямую.

Причина — на самой Pi:

```
137401  resolute-updates_InRelease                     получен нормально
     0  resolute-updates_main_binary-arm64_Packages    ПУСТО
     0  ... universe, multiverse, restricted            ПУСТО
```

Списки пакетов `-updates` нулевого размера, часть датирована днём сборки
образа — то есть так пришло прямо из образа. При `apt-get update` заголовок
`InRelease` не меняется, apt пишет `Hit` и продолжает доверять пустым спискам.
Для него `-updates` просто не существует.

Лечится сбросом кэша индексов:

```bash
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
```

**Делать сразу после первой загрузки, до установки чего-либо.**

Чего не делать: откатывать `packagekit` и прочие пакеты на архивные версии.
Это лечит симптом по одному пакету за раз, а следом сломается следующий.
Проверка, что починилось:

```bash
apt-cache policy packagekit   # должна появиться строка resolute-updates/main
```

По пути отвергнута версия «arm64 раздаётся только с ports.ubuntu.com»:
оба зеркала, `archive` и `ports`, отдают одинаковые версии в `-updates`.

## Рабочий стол, браузер, контейнеры (выполнено)

Сначала — перенос на NVMe и починка индексов apt (разделы выше), и только
потом установка. Иначе всё поставленное на SD пришлось бы переносить заново.

```bash
sudo apt-get install -y ubuntu-desktop-minimal incus
sudo usermod -aG incus-admin gadjet
sudo incus admin init --minimal
sudo reboot
```

Результат (927 новых пакетов):

| | |
|---|---|
| Рабочий стол | GNOME 50.1 + GDM, `graphical.target` по умолчанию |
| Браузер | Firefox 155 (snap — в Ubuntu он так и поставляется) |
| Контейнеры | Incus 6.0.5, минимальная инициализация, работает без sudo |
| Дисплей | `card1-DSI-1` connected, 800x480, экран входа GDM на нём |

GNOME выбран за поддержку сенсорного ввода и экранную клавиатуру — для 7"
тача это решающее. Минус — на 800x480 тесно; альтернатива полегче — XFCE/LXQt,
но у них заметно хуже с тачем.

Группа `incus-admin` применяется при следующем входе — поэтому перезагрузка.

## Сеть: адрес меняется между загрузками

`.156` (с SD) → `.158` (первая загрузка с NVMe) → `.157` (после установки
рабочего стола). MAC один и тот же: `2c:cf:67:6e:18:26`.

Причина последней смены: `ubuntu-desktop-minimal` ставит NetworkManager, и он
перехватывает `eth0` у systemd-networkd:

```
nmcli:      eth0:connected:netplan-eth0
networkctl: eth0  ether  unmanaged
```

У NM свой идентификатор DHCP-клиента, роутер счёл это новым устройством.
Дальше под NM адрес должен держаться, но **надёжно — только резерв на
роутере по MAC**. Статический адрес на самой Pi опасен, пока неизвестен
диапазон DHCP роутера: можно попасть в занятый.

Найти Pi, если адрес снова уехал:

```bash
for i in $(seq 1 254); do (ping -c1 -W1 192.168.10.$i >/dev/null &); done; sleep 5
ip neigh | grep -i 2c:cf:67
```

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

[[00-Проект]] · [[NixOS-на-Pi5]] · [[NixOS-на-Pi5]] · [[Грабли]]
