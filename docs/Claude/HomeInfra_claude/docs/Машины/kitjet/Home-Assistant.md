---
tags: [kitjet, home-assistant, haos, zigbee, libvirt, гайд]
---

# Home Assistant на kitjet

> **Статус: РАБОТАЕТ** (2026-09-10). HAOS 18.2 в VM на kitjet, свой адрес
> в домашней сети, Zigbee-донгл проброшен в VM. Данные HA **не восстановлены**
> — их нет в бэкапе, см. ниже.

| | |
|---|---|
| Адрес | `http://192.168.10.129:8123` |
| VM | `haos`, 4 ГБ, 2 vCPU, автозапуск включён |
| Диск | `/var/lib/libvirt/images/haos.qcow2` (32 ГБ вирт., на `vm-images`) |
| Сеть | мост `br0` → `enp5s0`, virtio, MAC `52:54:00:0a:15:d8` |
| Zigbee | CP2102 `10c4:ea60`, проброшен в VM |

## Почему HAOS в VM, а не контейнер или `services.home-assistant`

- **Магазин add-on'ов.** Zigbee2MQTT, Mosquitto, Node-RED ставятся в один клик.
  В контейнере и в NixOS-модуле их нет.
- **Бэкапы и восстановление** встроены в сам HA и переносят всё вместе с add-on'ами.
- **Свой адрес в сети** через мост: HA находит устройства в локальной сети
  (mDNS, Chromecast, ESPHome). Для этого нужен кабель — мост на Wi-Fi не делается.

Цена — VM создаётся командой, а не описывается во flake. Поэтому команда ниже.

## Бэкапа HA нет — ставили с нуля

Единственный бэкап — Proxmox, `/run/media/gadjet/backup/Server/Proxmox/dump/`.
В нём **только LXC-контейнеры**, VM нет вовсе:

| CT | Имя | Что внутри |
|---|---|---|
| 100 | MQTT | брокер Mosquitto |
| 101 | node-red | самодельный пульт: кнопки и слайдеры → MQTT |
| 102 | pairdrop | обмен файлами |
| 103 | webdav | WebDAV |
| 104 | Gadnginx | обратный прокси |

Проверено поиском внутри архивов: ни конфига HA, ни zigbee2mqtt, ни резервной
копии координатора. В потоках node-red нет узлов Home Assistant — только топики
`motor`, `VOLUME`, `hello` в брокер `192.168.21.145` (старая подсеть `.21`).

Значит, HA был VM, не попавшей в бэкап. **Zigbee-устройства придётся спаривать
заново** — ключа сети и базы устройств нигде нет.

Имена CT в Proxmox лежат в файлах `*.tar.zst.notes` рядом с архивами.
Заглянуть внутрь архива, не распаковывая:

```bash
zstd -dc vzdump-lxc-101-*.tar.zst | tar -t | grep -i zigbee
```

## Установка

### 1. Образ

```bash
cd ~/Downloads
curl -LO https://github.com/home-assistant/operating-system/releases/download/18.2/haos_ova-18.2.qcow2.xz
echo "254e53f354df0739e3afc09be5431a07df53f0df6b703885404f665c454f254e  haos_ova-18.2.qcow2.xz" | sha256sum -c
sudo sh -c 'xz -dc ~gadjet/Downloads/haos_ova-18.2.qcow2.xz > /var/lib/libvirt/images/haos.qcow2'
```

sha256 — поле `digest` у ассета в GitHub API релиза.

### 2. VM

```bash
sudo virt-install \
  --connect qemu:///system \
  --name haos \
  --memory 4096 --vcpus 2 --cpu host-passthrough \
  --os-variant generic \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
  --disk path=/var/lib/libvirt/images/haos.qcow2,bus=virtio,format=qcow2 \
  --network bridge=br0,model=virtio \
  --hostdev 0x10c4:0xea60 \
  --noautoconsole --import
sudo virsh autostart haos
```

| Флаг | Зачем |
|---|---|
| `--boot uefi,…secure-boot…enabled=no` | HAOS грузится только через UEFI, но **не** с Secure Boot. См. ловушку ниже |
| `--network bridge=br0` | свой адрес в домашней сети, а не NAT |
| `--hostdev 0x10c4:0xea60` | проброс Zigbee-донгла по vendor:product |
| `--import` | диск уже готов, установщик не нужен |
| `--cpu host-passthrough` | все инструкции процессора хоста, без эмуляции |

### 3. Найти адрес и дождаться HA

```bash
ip neigh | grep -i 52:54:00:0a:15:d8        # после пинг-развёртки подсети
curl -s -o /dev/null -w '%{http_code}' http://192.168.10.129:8123/
```

Адрес появился через ~10 с, HA ответил через ~50 с.

## Ловушка: автовыбор прошивки берёт Secure Boot

В `qemu/firmware/` два дескриптора для x86_64:

```
50-edk2-x86_64-secure.json   ← приоритет ВЫШЕ (меньше номер)
60-edk2-x86_64.json
```

Простое `--boot uefi` возьмёт вариант с Secure Boot, а HAOS не подписан
ключами Microsoft — не загрузится. Поэтому Secure Boot запрещён явно.
Проверка:

```bash
sudo virsh dumpxml haos | grep -E 'secure-boot|<loader'
# <feature enabled='no' name='secure-boot'/>
# <loader ...>/run/libvirt/nix-ovmf/edk2-x86_64-code.fd</loader>
```

## Проброс донгла

После старта VM донгл **исчезает с хоста** — `/dev/serial/by-id/` становится
пустым. Это нормально: USB-устройство целиком принадлежит VM. На kitjet им
больше ничего пользоваться не может.

## Что дальше

- [ ] Онбординг HA: учётная запись, место, единицы
- [ ] Zigbee: HA должен сам обнаружить донгл (интеграция ZHA). Либо поставить
      add-on Zigbee2MQTT — тогда нужен и Mosquitto
- [ ] Спарить Zigbee-устройства заново
- [ ] Настроить бэкапы HA — **чтобы следующий раз было что восстанавливать**
- [ ] Старые сервисы (MQTT, node-red, pairdrop, webdav, nginx) — вернуть как
      add-on'ы HA или контейнерами Incus на [[pintu]]: архивы Proxmox —
      это обычные rootfs, Incus умеет их импортировать
## Лишний HA в контейнере — убран (2026-09-13)

`modules/virtualisation.nix` держал два блока, приехавших копипастой из вики:
`virtualisation.oci-containers.containers.homeassistant` (образ
`ghcr.io/home-assistant/home-assistant:stable`, `TZ = Europe/Berlin`,
`--device=/dev/ttyACM0` с комментарием «Example, change this to match your own
hardware») и пустой `services.home-assistant`.

То есть **третий Home Assistant** в конфиге при одном настоящем — HAOS в VM.
Контейнер падал на каждом старте:

```
Error: stat /dev/ttyACM0: no such file or directory
podman-homeassistant.service: Main process exited, code=exited, status=125
podman-homeassistant.service: start-limit-hit
```

Устройства `/dev/ttyACM0` на kitjet нет вообще: донгл — CP2102, он приходит как
`/dev/ttyUSB0` (`/dev/serial/by-id/usb-Silicon_Labs_CP2102_…`). И чинить путь
было бы ошибкой: донгл уже проброшен в VM, два HA на одно устройство не делятся.

Из-за этого юнита kitjet висел в `degraded` — при живых остальных сервисах:

```bash
systemctl is-system-running   # degraded
systemctl --failed            # podman-homeassistant.service
```

Оба блока удалены. **Проверять `systemctl is-system-running` после каждого
`switch`** — упавший юнит сам о себе не скажет.

## Core не отвечает (открыто с 2026-09-13)

VM `haos` работает, но веб-интерфейс на `192.168.10.129:8123` недоступен —
`connection refused`. При этом сама HAOS жива:

| проверка | результат |
|---|---|
| `virsh -c qemu:///system dominfo haos` | running, 4 ГБ, CPU time 10460 с |
| `ping 192.168.10.129` | 0% потерь |
| порт 4357 (observer) | открыт: Supervisor **Connected**, Support **Supported**, Health **Healthy** |
| порт 8123 (core) | **закрыт** |
| порт 22 | закрыт (add-on SSH не ставился) |

Значит, упала не виртуалка и не supervisor, а именно **Home Assistant Core**.
Смотреть изнутри — консолью VM с kitjet:

```bash
virsh -c qemu:///system console haos   # выход: Ctrl+]
# в HAOS:
ha core info
ha core logs
ha core start
```

Связи с убранным контейнером нет: тот никогда не стартовал и донгл не отнимал.
Возможная причина — незавершённый онбординг (первый пункт «Что дальше» так и
не отмечен) либо падение после обновления.


## Сеть kitjet: трафик всё ещё идёт через Wi-Fi

После подключения кабеля Wi-Fi остался включён, и у него метрика меньше:

```
default via 192.168.10.1 dev wlp2s0f0u9  metric 100    ← выигрывает
default via 192.168.10.1 dev br0         metric 1003
```

На VM это не влияет — она на мосту. Но сам kitjet ходит в сеть по Wi-Fi.
Для сервера это неправильно; поправить — отключить Wi-Fi или поменять метрики.


[[00-Проект]] · [[kitjet]] · [[pintu]] · [[Грабли]]
