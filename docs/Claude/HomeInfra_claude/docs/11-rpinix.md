---
tags: [хост, rpinix, pi5, установка]
---

# rpinix — Raspberry Pi 5 на NixOS

Гайд по установке NixOS на Pi5 вместо Proxmox и переделке роли: от гипервизора к контейнерам.

## Переосмысление архитектуры

**Было:** HAOS + aarch64-VM на Pi5 (утяжеляет систему, 6+ ГБ RAM).
**Стало:** контейнеры на Pi5 (lightweigh), HAOS как VM на kitjet (мощнее).

### Новые роли машин

| Хост | Роль | ОЗУ | Что запускать |
| --- | --- | --- | --- |
| **kitjet** | сервер: хранилище, гипервизор | 16 ГБ | ZFS, Jellyfin, HAOS (VM), KVM-образы |
| **rpinix** | Pi5: контейнеры, реплика | 8 ГБ | Podman, бэкапы ZFS, лёгкие сервисы |
| **gadnix** | PC: работа, игры | 32 ГБ | niri, браузер, RDP, VS Code |

### Что меняется в конфиге

Старое (`modules/kiosk.nix`):

```nix
virtualisation.libvirtd.enable = true;    # ← убрать
programs.cage.enable = true;               # ← убрать (kiosk)
services.home-assistant.enable = true;    # ← убрать (идёт на kitjet)
```

Новое (`modules/container.nix`):

```nix
virtualisation.podman.enable = true;
virtualisation.oci-containers.containers = {
  # сюда лёгкие контейнеры: nginx, PostgreSQL, influxdb, etc.
};
```

**Главное:** ZFS, реплики, backup-логика **не меняются**. Pi5 остаётся приёмником `tank/backup` из kitjet.

## Установка NixOS на Pi5

### Требования

- **Raspberry Pi 5** с 8 ГБ RAM (проверено на этой конфигурации)
- **NVMe 1 ТБ** (в адаптере M.2 to USB, подключённый по USB 3.0)
- **Интернет** (для скачивания пакетов)
- **Другая машина** с Linux/macOS для записи SD-карты
- `nixos-aarch64-sd-image` — образ для Pi 5

### Шаг 1: Скачать образ NixOS

```bash
# На машине, с которой будешь писать образ
cd /tmp
wget https://hydra.nixos.org/build/XXXXXXX/download/1/nixos-sd-image-24.11-aarch64-linux.img.zst
# или для unstable (рекомендуется для Pi5):
wget https://hydra.nixos.org/build/XXXXXXX/download/1/nixos-sd-image-unstable-aarch64-linux.img.zst
```

Актуальные ссылки найди на https://channels.nixos.org/ → `nixos-unstable` → `latest-iso` → `sd-image-aarch64`.

### Шаг 2: Написать на SD-карту

```bash
# Найти устройство SD-карты
lsblk -d -o NAME,SIZE,MODEL

# Распаковать и написать (осторожно! -if /dev/zero стирает!)
zstd -d nixos-sd-image-unstable-aarch64-linux.img.zst -o nixos.img
sudo dd if=nixos.img of=/dev/sdX bs=4M status=progress
sudo sync
```

Замени `sdX` на actual устройство (например, `sdb`, **не** `sdb1`!).

### Шаг 3: Загрузиться с SD и поднять сеть

1. Вставь SD-карту в Pi5
2. Подключи экран (HDMI) + клавиатуру (USB)
3. Подключи Pi5 к сети (Ethernet или Wi-Fi через меню)
4. Включи питание

На экране увидишь `login:` → вход как `root` без пароля.

### Шаг 4: Подготовить NVMe

```bash
# На Pi в login-сессии root
sudo su -

# Найти NVMe
lsblk

# Партиционировать: GPT с разделом для NixOS
parted /dev/nvme0n1 mklabel gpt
parted /dev/nvme0n1 mkpart ESP fat32 1MiB 513MiB
parted /dev/nvme0n1 mkpart primary ext4 513MiB 100%
parted /dev/nvme0n1 set 1 boot on

# Файловые системы
mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
mkfs.ext4 -L nixos /dev/nvme0n1p2

# Примонтировать
mount /dev/nvme0n1p2 /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
```

### Шаг 5: Сгенерировать hardware-configuration

```bash
nixos-generate-config --root /mnt

# Это создаст /mnt/etc/nixos/hardware-configuration.nix
# Скопировать его в репозиторий:
cat /mnt/etc/nixos/hardware-configuration.nix
# (выписать руками или передать через SSH)
```

### Шаг 6: Создать configuration.nix для Pi5

На машине, где лежит репозиторий (kitjet):

```bash
# Скопировать hardware-config
cp /mnt/etc/nixos/hardware-configuration.nix ~/nixos/hosts/rpinix/

# Создать базовый конфиг (см. шаблон ниже)
cat > ~/nixos/hosts/rpinix/default.nix <<'CONF'
{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    # ../../modules/container.nix    # когда создашь
    # ../../modules/backup.nix       # когда создашь
  ];

  networking.hostName = "rpinix";
  networking.hostId = "<8 hex из head -c 8 /etc/machine-id>";

  # aarch64 + Pi5 требует unstable
  # (flake.nix это уже определяет, но для подстраховки можно указать явно)

  boot.loader.raspberryPi = {
    enable = true;
    version = 5;
  };

  # Pi5 нет ни UEFI, ни systemd-boot — используется proprietary bootloader
  boot.kernelPackages = pkgs.linuxPackages_6_6;   # LTS, аппаратная поддержка Pi5

  # Минимум системы: SSH, NTP, firewall
  services.openssh.enable = true;
  services.openssh.openFirewall = true;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];    # SSH только, остальное при надобности

  # Статический адрес (опционально, но рекомендуется для сервера)
  # networking.interfaces.eth0.ipv4.addresses = [{
  #   address = "192.168.1.100";
  #   prefixLength = 24;
  # }];

  system.stateVersion = "24.11";    # или unstable версия
}
CONF
```

### Шаг 7: Собрать конфиг на kitjet

На machine-A (kitjet) из репозитория:

```bash
cd ~/nixos
git add hosts/rpinix/
nix build .#nixosConfigurations.rpinix.config.system.build.sdImage --no-link
```

Это создаст **SD-образ** со всеми твоими конфигурациями. Он больше, чем базовый, потому что содержит systemd, модули и твои программы.

### Шаг 8: Написать результат на флешку

Полученный образ скопировать на флешку и загрузиться с неё на Pi:

```bash
# На машине с выходом в интернет (может быть машина, с которой делал dd на шаге 2)
# Скопировать образ с kitjet
scp gadjet@kitjet:~/result-*-sd-image /tmp/

# Написать на флешку
zstd -d <образ>.img.zst -o sd.img
sudo dd if=sd.img of=/dev/sdX bs=4M status=progress
```

### Шаг 9: Первая загрузка

1. Вставь флешку/SD в Pi5
2. Включи, жди ~2 мин загрузки
3. Войди по SSH:

```bash
ssh root@rpinix.lan      # если DHCP выдаст имя
# или
ssh root@192.168.1.<IP>  # явный адрес, найди в роутере
```

Пароль — пусто (ты сам себе добавишь ключ в конфиге позже).

### Шаг 10: Обновить конфиг в flake.nix

```nix
# flake.nix
hosts = {
  kitjet = { system = "x86_64-linux"; home = ./home/kitjet.nix; };
  rpinix = { system = "aarch64-linux"; home = null; };  # ← добавить
};
```

## Модули для rpinix

После успешной первой загрузки создать модули:

**`modules/container.nix`** — Podman для контейнеров вместо KVM:

```nix
{ config, pkgs, lib, ... }:
{
  # Podman вместо Docker (лучше с NixOS)
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
  };

  # OCI-контейнеры (декларативно из конфига)
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      # Пример:
      # nginx = {
      #   image = "nginx:latest";
      #   ports = ["80:80"];
      # };
    };
  };
}
```

**`modules/backup.nix`** — приёмник реплик ZFS:

```nix
{ config, pkgs, lib, ... }:
{
  # ZFS пулы для приёма реплик (если есть)
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs.autoScrub.enable = true;
}
```

**`hosts/rpinix/default.nix`** (итоговый):

```nix
{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/container.nix      # Podman + OCI
    # ../../modules/backup.nix       # включить, когда ZFS пул создадите
  ];

  networking.hostName = "rpinix";
  networking.hostId = "...";

  boot.loader.raspberryPi = {
    enable = true;
    version = 5;
  };

  boot.kernelPackages = pkgs.linuxPackages_6_6;

  services.openssh.enable = true;

  system.stateVersion = "24.11";
}
```

## Проблемы и решения

**«Boot hangs on Rainbow Screen»** — Pi5 нашла SD, но конфиг не подходит.
- Проверить, что `boot.loader.raspberryPi.version = 5`.
- Убедиться, что используется correct kernel для Pi5.

**«No space left on device»** — NVMe-раздел слишком мал.
- Пересоздать разделы больше (шаг 4).

**«Cannot import ZFS» — если потом решишь хранить пулы на Pi**.
- Убедиться, что `boot.supportedFilesystems = [ "zfs" ]`.
- Может потребоваться свежее ядро из unstable.

**SSH работает, но без ключей** — по умолчанию вход по паролю (пусто).
- Добавить публичный ключ в конфиг (`openssh.authorizedKeys.keys`).
- Выключить `PasswordAuthentication` после проверки ключа.

## Что дальше

- [ ] HAOS как VM на kitjet (см. планы в [[10-kitjet]])
- [ ] Podman-контейнеры на rpinix
- [ ] ZFS-репликация kitjet → rpinix
- [ ] `sops-nix` для секретов в контейнерах

[[00-Проект]] · [[10-kitjet]] · [[20-Бэкапы]] · [[21-ZFS-хранилище]]
