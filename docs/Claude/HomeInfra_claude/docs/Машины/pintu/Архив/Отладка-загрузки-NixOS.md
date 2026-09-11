---
tags: [rpinix, pi5, диагностика, загрузка]
---

# rpinix — диагностика загрузки (замирание на vc4-drm)

Состояние на 2026-09-09: образ собирается, Pi 5 стартует с NVMe, но экран
замирает на строке

```
vc4-drm axi:gpu: bcm2712_iommu_of_xlate: MMU 1000005200.iommu
```

HDMI дальше не обновляется, DSI пустой, по сети машина не появляется
(ping-развёртка `192.168.10.0/24` с kitjet — ни одного MAC из диапазонов
Raspberry Pi: `2c:cf:67`, `d8:3a:dd`, `dc:a6:32`, `e4:5f:01`, `b8:27:eb`).

## Главное: это ДВА разных вопроса

Не смешивать, иначе ищешь не там:

1. **Почему замер экран.** Скорее всего не «зависание», а передача консоли:
   vc4 поднимает KMS, firmware-framebuffer уходит, fbcon не переезжает на
   новое DRM-устройство → картинка остаётся на последнем кадре. Система при
   этом может спокойно грузиться дальше.
2. **Докуда реально дошла загрузка.** Отвечает только лог, а не экран.

## Проверенные версии, которые НЕ подтвердились

Обе выглядели убедительно и обе оказались мимо. Записано, чтобы не проверять
второй раз.

### Неверный оверлей vc4 — НЕТ

`raspberry-pi-nix` в секции `[all]` безусловно пишет `dtoverlay=vc4-kms-v3d`,
без учёта платы. Выглядит как баг: generic `.dtbo` не содержит `compatible`
на `bcm2711`/`bcm2712` (он для Pi 1–3), отдельные `vc4-kms-v3d-pi4.dtbo` и
`vc4-kms-v3d-pi5.dtbo` в прошивке лежат.

Но имя подменяет **сама прошивка**. В `overlays/overlay_map.dtb` есть правило
`vc4-kms-v3d` → `-pi4` для `bcm2711` и → `-pi5` для `bcm2712`, а каталог
`overlays/` копируется в раздел FIRMWARE целиком
(`sd-image/default.nix`, строка 49). Значит на Pi 5 фактически грузится
`vc4-kms-v3d-pi5`. Переопределять вручную не нужно.

Проверка содержимого `.dtbo` без `dtc` и `strings`:

```bash
D=$(dirname $(find /nix/store -maxdepth 4 -name 'vc4-kms-v3d-pi5.dtbo' | head -1))
tr -c '[:print:]' '\n' < $D/overlay_map.dtb | grep -nE 'vc4-kms|bcm271'
```

### Два `root=` в cmdline — НЕТ

В `boot.kernelParams` действительно два:

```
root=PARTUUID=2178694e-02 ... root=fstab
```

`root=fstab` — не мусор и не опечатка, а штатный механизм systemd-initrd:
опция `boot.initrd.systemd.root` (nixpkgs, `system/boot/systemd/initrd.nix:532`)
по умолчанию равна `"fstab"` и означает «монтируй корень по `fileSystems`,
запечённым в initrd». Ядро тут `root=` не разбирает — это делает initrd.
Параметр от `sd-image` просто избыточен.

## Что делать дальше — по порядку

### Шаг 1. Прочитать журнал с NVMe (самое дешёвое, ничего не пересобирает)

Загрузиться с SD, подключить NVMe и посмотреть, что успело записаться:

```bash
lsblk -o NAME,SIZE,LABEL,FSTYPE
sudo mkdir -p /mnt/nvme
sudo mount /dev/nvme0n1p2 /mnt/nvme
sudo journalctl -D /mnt/nvme/var/log/journal --no-pager | tail -100
```

Интерпретация:

- **журнал есть и обрывается на чём-то осмысленном** → загрузка шла долго,
  причина видна прямо в конце;
- **каталога `/mnt/nvme/var/log/journal` нет или он пуст** → до записи журнала
  не дошло, останов ранний (initrd / монтирование корня);
- **корень вообще не растянулся** (`lsblk` показывает раздел ~2 ГБ вместо 238) →
  не отработал `expand-root-partition`.

### Шаг 2. Убрать KMS и увидеть остаток загрузки на HDMI

Раздел FIRMWARE — обычный vfat, `config.txt` правится **напрямую, без
пересборки образа**. Это главный инструмент быстрой итерации.

```bash
sudo mount /dev/nvme0n1p1 /mnt/fw
sudo cp /mnt/fw/config.txt /mnt/fw/config.txt.bak
sudo sed -i 's/^dtoverlay=vc4-kms-v3d$/#&/' /mnt/fw/config.txt
sudo umount /mnt/fw
```

Без KMS консоль остаётся на простом firmware-framebuffer и HDMI продолжает
печатать до конца загрузки. Если после этого система догружается и отвечает
по сети — проблема была только в передаче консоли, а не в загрузке.

Вернуть обратно: `sudo cp /mnt/fw/config.txt.bak /mnt/fw/config.txt`.

### Шаг 3. Serial console (если есть USB-TTL)

Уже всё настроено, докупать в конфиг ничего не надо:

- `enable_uart=1` есть в сгенерированном `config.txt`;
- `console=serial0,115200n8` есть в `kernelParams`
  (`raspberry-pi-nix.serial-console.enable` по умолчанию `true`).

Подключение: GPIO 6 (GND), 8 (TXD), 10 (RXD), скорость 115200.
UART отдаёт весь лог, включая то, что происходит после смерти HDMI-консоли.

### Шаг 4. Если выяснится, что дело в сети, а не в загрузке

Отдельно проверить: live-система с SD получала адрес `192.168.10.157`.
Если она сидела на Wi-Fi, а не на Ethernet, то у установленной системы
никаких Wi-Fi-кредов нет и по сети её не будет **при полностью исправной
загрузке**. В `modules/common.nix` включён только NetworkManager
(`networking.networkmanager.enable = true`), профилей Wi-Fi в репозитории нет.

## Полезные проверки без сборки

```bash
cd ~/nixos
# итоговый config.txt (это строковая опция, сборка не нужна)
nix eval --raw .#nixosConfigurations.rpinix.config.hardware.raspberry-pi.config-generated
# итоговый cmdline
nix eval --json .#nixosConfigurations.rpinix.config.boot.kernelParams
```

[[NixOS-на-Pi5]] · [[NixOS-на-Pi5]] · [[Грабли]]

---

## Осмотр живой машины 2026-09-09 (по SSH с kitjet)

Подключение: `sshpass -p 1414 ssh nixos@192.168.10.157` (live-система с SD).

### Факт 1. Корень на NVMe никогда не загружался

```
/mnt/nvme/  →  lost+found  nix/  nix-path-registration  run/  sbin/
```

Ни `/etc`, ни `/var`, ни `/home`. Это **ровно то**, что кладёт сборщик образа:
закрытие nix-стора плюс `/sbin/init`. Каталоги `/etc` и `/var` создаёт активация
на первой загрузке (stage-2). Их отсутствие означает, что stage-2 не отработал
ни разу — останов в initrd или на переходе к нему. Раздел так и остался 4.7 ГБ
вместо 238, `expand-root-partition` тоже не запускался.

`/sbin/init` при этом целый — не симлинк, а скрипт:

```
#!/nix/store/…-bash-interactive-5.3p9/bin/bash
exec /nix/store/…-nixos-system-rpinix-26.05.20260905.6713828/init
```

Раздел FIRMWARE тоже в порядке: `kernel.img` 35 МБ, `initrd` 22 МБ,
`bcm2712-rpi-5-b.dtb` на месте, занято 79 МБ из 128 — обрезания не было.

### Факт 2. SD и NVMe неразличимы для загрузчика

```
mmcblk0p1  FIRMWARE  2178694e-01      nvme0n1p1  FIRMWARE  2178694e-01
mmcblk0p2  NIXOS_SD  2178694e-02      nvme0n1p2  NIXOS_SD  2178694e-02
```

Одинаковые метки И одинаковые PARTUUID. Причина: `sdImage.firmwarePartitionID`
в модуле — константа (`0x2178694e`), поэтому её получает **любой** NixOS
sd-image. А в `cmdline.txt` стоит `root=PARTUUID=2178694e-02`.

Пока SD вынута — однозначно. Но с обеими вставленными `root=PARTUUID=…` и
`/dev/disk/by-label/NIXOS_SD` указывают неизвестно куда, и это мина.
Лечится заданием своего `sdImage.firmwarePartitionID` для rpinix.

### Факт 3. Стандартный образ nixpkgs на этой плате грузится

Live-система на SD — обычный `sd-image-aarch64` из 26.05, ядро **7.2.4**.
Её `config.txt` начинается с `kernel=u-boot.bin`, в разделе лежит
`u-boot.bin` (943 КБ) и `armstub8-gic.bin`, а `kernel.img`/`initrd`/`cmdline.txt`
там **нет вообще** — ядро ищет U-Boot через `extlinux.conf` на корне.

В этом `u-boot.bin` есть команда `nvme` и 11 ссылок на PCIe, то есть загрузка
с NVMe для него в принципе доступна.

Отсюда следует пересмотр: `raspberry-pi-nix` мы взяли из-за утверждений,
которые в 26.05 уже неверны. См. исправленный раздел в [[NixOS-на-Pi5]].

### Что сделано для следующей загрузки

На NVMe в `config.txt` закомментирован KMS (бэкап — `config.txt.bak`):

```
#dtoverlay=vc4-kms-v3d
```

Без KMS консоль остаётся на firmware-framebuffer, и HDMI должен печатать
сообщения до самого конца, а не замирать на `vc4-drm … bcm2712_iommu_of_xlate`.
Это отвечает на вопрос, зависание там или просто потеря консоли.

---

## Загрузка без KMS: где на самом деле обрыв (2026-09-09, вечер)

Снятие `dtoverlay=vc4-kms-v3d` сработало — HDMI больше не замирает на vc4,
лог идёт дальше. Фото: `IMG_20260909_201318498.jpg`.

Ключевые строки:

```
[4.276498] systemd[1]: Running in initrd.
[4.305863] systemd[1]: Hostname set to <rpinix>.
[4.466767] systemd[1]: Expecting device /dev/disk/by-label/NIXOS_SD...
[5.248516] macb 1f00100000.ethernet end0: renamed from eth0
[5.849823] EXT4-fs (nvme0n1p2): mounted filesystem ... r/w with ordered data mode
```

**Значит initrd отработал полностью:**

- systemd-initrd стартовал (`boot.initrd.systemd.enable = true`, проверено `nix eval`);
- устройство по метке `NIXOS_SD` найдено;
- сетевой интерфейс поднялся и переименован в `end0`;
- **корень примонтирован**: `nvme0n1p2`, ext4, r/w, на 5.85 с.

Обрыв — **сразу после монтирования корня, на переходе stage-1 → stage-2
(switch-root)**. Дальше ни одной строки, курсор моргает (ядро живо).

Это снимает целый класс версий: дело не в поиске корня, не в PARTUUID,
не в метках, не в ext4 и не в NVMe как таковом. Всё это отработало.

### Проверка «а может, просто потерялась консоль»

Версия была такая: в cmdline `console=tty1 console=serial0,115200n8`, а
**основным `/dev/console` становится последний** в списке, то есть UART.
Логи initrd идут через `/dev/kmsg` и попадают на все консоли (поэтому видны),
а вывод stage-2 — уже в `/dev/console`, то есть в UART. На HDMI пусто.

**Версия не подтвердилась.** Ping-развёртка `192.168.10.0/24` с kitjet после
зависания не находит ни одного MAC из диапазонов Raspberry Pi
(`2c:cf:67`, `d8:3a:dd`, `dc:a6:32`, `e4:5f:01`, `b8:27:eb`). Если бы stage-2
отработал, поднялся бы sshd и машина была бы в сети. Значит это настоящий
останов, а не только потеря вывода.

Но порядок консолей всё равно надо поменять — иначе мы не увидим сообщение
об ошибке, даже когда оно появится.

### Ошибка в моей прошлой проверке `/sbin/init`

Я проверял так:

```bash
T=$(readlink /mnt/nvme/sbin/init); test -e "/mnt/nvme$T"
```

`/sbin/init` здесь **не симлинк**, а обычный файл-скрипт, поэтому `readlink`
вернул пустую строку и проверка выродилась в `test -e /mnt/nvme` — всегда
истина. Целостность стора этим не проверена. Перепроверить явно:

```bash
sudo grep -o '/nix/store/[^ ]*' /mnt/nvme/sbin/init | while read p; do
  printf '%s: ' "$p"; test -e "/mnt/nvme$p" && echo OK || echo ОТСУТСТВУЕТ
done
```

### Что делать дальше

Загрузиться с SD и с неё править раздел FIRMWARE на NVMe.

**Шаг A. Сделать tty1 основной консолью** — чтобы вывод stage-2 шёл на HDMI:

```bash
sudo mount /dev/nvme0n1p1 /mnt/fw
sudo sed -i 's/console=tty1 console=serial0,115200n8/console=serial0,115200n8 console=tty1/' /mnt/fw/cmdline.txt
```

**Шаг B. Проверить стор** командой из предыдущего раздела.

**Шаг C. Если и после этого пусто** — переходить на стандартный
`sd-image-aarch64`. Он на этой плате доказанно грузится (это и есть live-SD),
использует U-Boot, у которого есть поддержка NVMe, и его отладка идёт через
внятный вывод U-Boot, а не через молчание.

---

## Развязка: Pi 5 поддержан в unstable, а не в 26.05 (2026-09-09, ночь)

Сравнение `nixos/modules/installer/sd-card/sd-image-aarch64.nix` в двух ветках:

| | nixos-26.05 | nixos-unstable |
|---|---|---|
| секции `[pi5]`, `[cm5]` | нет | **есть** |
| `bcm2712-*.dtb` | не копируются | **копируются все 7** |
| U-Boot | только `u-boot-rpi3.bin`, `u-boot-rpi4.bin` | **`ubootRaspberryPiAarch64` → `u-boot.bin`** |

Это ровно то, что лежит на рабочей live-SD. То есть SD собрана из unstable,
и **Pi 5 в nixpkgs поддержан штатно** — просто не в стабильной ветке.
Обновление 26.05 не помогает: проверено, после `nix flake update nixpkgs`
секции `[pi5]` там по-прежнему нет.

`CLAUDE.md` с самого начала говорил «rpinix на nixpkgs-unstable», но
`flake.nix` этого не делал — все хосты собирались из 26.05.

### Что изменено

`flake.nix`: хост может выбрать свою ветку nixpkgs.

```nix
mkHost = name: cfg:
  let np = cfg.nixpkgs or nixpkgs;   # не указал — берётся основная
  in np.lib.nixosSystem { ... };
```

```nix
rpinix = {
  system = "aarch64-linux";
  home = null;
  nixpkgs = inputs.nixpkgs-unstable;
  extraModules = [
    "${inputs.nixpkgs-unstable}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
  ];
};
```

`raspberry-pi-nix` удалён из inputs целиком — вместе с его вендорным ядром,
пином на январь 2025, отдельным кэшем и багом `tpm-crb`.

`hosts/rpinix/default.nix`: убраны `raspberry-pi-nix.board` и
`boot.initrd.systemd.tpm2.enable` (оба относились к вендорному ядру),
добавлены разные метки разделов.

### Метки разделов разведены

По умолчанию **любой** NixOS sd-image получает `FIRMWARE`/`NIXOS_SD` и
`firmwarePartitionID = 0x2178694e`, поэтому SD и NVMe неразличимы. Теперь:

```nix
sdImage = {
  firmwarePartitionID = "0x52504958";   # не 0x2178694e
  firmwarePartitionName = "RPINIXFW";   # метка FAT, максимум 11 символов
  rootVolumeLabel = "RPINIX";           # вместо NIXOS_SD
};
```

Теперь SD можно держать вставленной, не рискуя загрузиться не с того диска.

### Побочный выигрыш: консоль

Новый cmdline (проверено `nix eval`):

```
console=ttyS0,115200n8 console=ttyAMA0,115200n8 console=tty0 root=fstab loglevel=7 …
```

`console=tty0` стоит **последним**, а основным `/dev/console` становится
именно последний. Значит вывод stage-2 пойдёт на HDMI, и прошлая проблема
с невидимым логом не повторится.

Ядро — **6.18.49** mainline, а не вендорное 6.6.51.

## Грабли инфраструктуры: git под root

`nix flake update` и любая сборка из рабочего репозитория падали с

```
error: insufficient permission for adding an object to repository database .git/objects
fatal: cannot create an empty blob in the object database
```

Причина: каталог `.git/objects/e6/` и файл
`e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` принадлежали root. Это хеш
**пустого блоба** в git — отсюда и формулировка про empty blob. Где-то git
запускался через sudo.

```bash
sudo chown -R gadjet:users /home/gadjet/nixos/.git/objects/e6
find /home/gadjet/nixos/.git -not -user gadjet    # должно быть пусто
```

Правило: `git` в этом репозитории **никогда** не запускать под sudo.

---

## Тупик U-Boot: он не умеет NVMe (2026-09-09, поздний вечер)

Штатный образ записан на NVMe, SD вынута — на HDMI заставка и всё.
Сети нет, Ctrl+Alt+F1..F4 не работают (их и не должно быть: до Linux
дело не доходит).

Причина найдена разбором самого бинаря `ubootRaspberryPiAarch64`
(его можно скачать из кэша и смотреть прямо на kitjet, Pi не нужна):

```bash
nix build --no-link --print-out-paths --impure --expr \
  '(builtins.getFlake "git+file:///home/gadjet/nixos").inputs.nixpkgs-unstable.legacyPackages.aarch64-linux.ubootRaspberryPiAarch64'
tr -c '[:print:]' '\n' < <путь>/u-boot.bin | grep 'boot_targets='
```

Результат:

```
boot_targets=mmc usb pxe dhcp
```

**NVMe в списке нет.** U-Boot перебирает SD, USB, PXE, DHCP — и всё.
Поэтому он стартует, ничего загрузочного не находит и останавливается.
Сообщение об этом уходит в UART; на HDMI текст U-Boot не рендерится,
видна только заставка прошивки.

Переопределять `boot_targets` бессмысленно — драйвера тоже нет:

| строка | вхождений |
|---|---|
| `nvme_scan`, `Identify`, `Namespace`, `nvme_` | **0** |
| `pcie`, `brcmstb` | 11, 3 |

Есть только имя команды `nvme` и PCIe-контроллер. Блочного драйвера NVMe
в сборке нет.

**Вывод: с NVMe этот U-Boot не грузится. `sd-image-aarch64` годится для
SD-карты, но не для NVMe.**

Это ровно то, о чём говорила документация `raspberry-pi-nix`:
`uboot.enable = false` нужен «для менее типичных схем, например загрузки
с NVMe». Тогда я это отбросил — зря.

### Ошибочный совет про enable_uart

Я предложил поменять `enable_uart=0` на `1` в секции `[pi5]`, чтобы «увидеть
лог U-Boot на HDMI». Это неверно дважды: `enable_uart` управляет
последовательным портом, а не выводом на HDMI, и апстрим ставит там `0`
намеренно — чтобы U-Boot не ловил призрачный ввод с плавающего UART
(bugzilla.opensuse.org, баг 1251192). **Вернуть обратно `enable_uart=0`.**

### Остающийся путь: грузиться прошивкой напрямую, без U-Boot

Родная схема Pi 5 для NVMe: EEPROM читает FAT-раздел и загружает ядро сам.

```
EEPROM (BOOT_ORDER=NVMe) → FIRMWARE (vfat) → config.txt
   → kernel (Image) + initramfs + bcm2712-rpi-5-b.dtb → корень (ext4)
```

U-Boot в ней не участвует. Это то, что делал `raspberry-pi-nix`, и та
попытка доходила до `EXT4-fs (nvme0n1p2): mounted filesystem r/w`, то есть
**дальше U-Boot-проблемы она уже была**. Вставала на switch-root, но с
вендорным ядром 6.6.51 и, что важно, с `console=serial0` последним в
cmdline — то есть вывод stage-2 уходил в UART и мы его просто не видели.

Теперь у нас mainline 6.18.49 и `console=tty0` последним. Проверить схему
можно **вручную, без единой пересборки**: скопировать ядро и initrd из
`/boot` на корне NVMe в FAT-раздел и написать свои `config.txt` и
`cmdline.txt`. Если загрузится — оформить это в Nix через
`sdImage.populateFirmwareCommands`.

---

# РАЗВЯЗКА: система работает (2026-09-10)

Итоговая рабочая конфигурация и порядок установки — [[NixOS-на-Pi5]].
Здесь только то, чем закончилась цепочка отладки.

```
rpinix, ядро 6.18.49 mainline, NixOS 26.11.20260905 (Zokor)
/      → /dev/nvme0n1p1 (RPINIXROOT)  234 ГБ, занято 3.2 ГБ
/boot  → /dev/mmcblk0p2 (SD)
```

## Последние две причины

После того как консоль наконец заработала, лог показал таймаут ожидания
`/dev/disk/by-label/RPINIXROOT` и **полное отсутствие строк про PCIe**.
Фото: `Image/2026-09-10-emergency-mode-нет-RPINIXROOT.jpg`.

Причин оказалось две, независимых.

**1. Драйвер контроллера PCIe — модуль, и его не было в initrd.**
Проверяется по `System.map` ядра, где перечислены встроенные символы:

```bash
grep -c brcm_pcie <ядро>/System.map   # 0   → модуль
grep -c dw_pcie   <ядро>/System.map   # 129 → встроен
```

Поэтому внутренний RP1 (USB, Ethernet) поднимался, а внешний разъём нет.
Лечится `boot.initrd.kernelModules = [ "pcie_brcmstb" ]`.

**2. В mainline-DTB внешний разъём выключен:** `pcie@1000100000` имел
`status = "disabled"`. Лечится оверлеем `hardware.deviceTree`.

Обе нужны одновременно: без модуля включать нечего, без DTB — модулю не к чему
привязаться.

## Ловушка: оверлей может не примениться молча

Первая версия оверлея не сработала. Сборка прошла успешно, ошибок не было,
но в собранном DTB узел остался `disabled`.

Причина в `apply_overlays.py` из nixpkgs:

```python
elif not overlay.compatible.intersection(dt_compatible):
    print(f"  Skipping overlay {overlay.name}: ... incompatible ...")
    continue
```

Без `compatible` в корне оверлея множество пустое, пересечение пустое, оверлей
отбрасывается. Целевой DTB объявляет `"raspberrypi,5-model-b"` и `"brcm,bcm2712"`.

**Успешная сборка не означает, что оверлей применён.** Проверять только так:

```bash
fdtget <dtbs>/broadcom/bcm2712-rpi-5-b.dtb /axi/pcie@1000100000 status
```

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

## Отвергнутые версии (все проверены, все неверны)

| Версия | Чем опровергнута |
|---|---|
| неверный оверлей `vc4-kms-v3d` | прошивка сама подменяет имя через `overlay_map.dtb` |
| два `root=` в cmdline | `root=fstab` — штатный механизм systemd-initrd |
| потеря консоли объясняет всё | машины не было в сети, то есть был настоящий останов |
| столкновение ядра и initrd в памяти | `kernel_addr_r` 0.5 МиБ + 61 МиБ < `scriptaddr` 84 МиБ |
| дело в размере ядра | у рабочей live-системы ядро 61.0 МиБ против наших 61.3 |

[[NixOS-на-Pi5]] · [[NixOS-на-Pi5]] · [[Грабли]]
