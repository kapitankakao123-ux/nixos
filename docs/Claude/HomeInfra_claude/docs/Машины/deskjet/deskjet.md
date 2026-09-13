---
tags: [хост, deskjet, nixos, установка, гайд]
---

# deskjet — домашний ПК

> **Статус: NixOS стоит и работает** (2026-09-13). Машина загружается с
> ядра zen 7.1.10, `/home` с Arch подхватился целиком, репозиторий склонирован
> в `~/nixos` — теперь рабочая копия есть и здесь, не только на kitjet.
> Осталось довести мелочи из раздела «После установки».

Имя — пара к `kitjet`: кухонный и настольный. Раньше звался `gadnix`,
рабочее имя `desktop`.

## Железо (снято с живого Arch)

| | |
|---|---|
| Процессор | AMD Ryzen 7 5700X, 8 ядер / 16 потоков |
| Память | 31 ГБ |
| Видео | **Radeon RX 9060 XT 16 ГБ** — Navi 44, архитектура **RDNA4**, `[1002:7590]` |
| Сеть | Realtek RTL8111 (`r8169`), 1 Гбит/с |
| Диск | один NVMe 1 ТБ |
| Загрузка | UEFI (на Arch — GRUB) |

## Роли

- **игры** — Steam, Proton, Lutris, Heroic
- **браузер**
- **работа** — RDP, WinBox, LibreOffice, VS Code
- **оболочка** — niri + DMS, общая с [[kitjet]] через `modules/desktop.nix`

Ни виртуалок, ни хранилища: `virtualisation.nix` и `storage.nix` не импортируются.

## Главное: `/home` не трогаем

Диск уже разбит так, что домашняя папка на **отдельном разделе**:

```
nvme0n1p1    1 ГБ  vfat   /boot   → ФОРМАТИРУЕТСЯ, метка BOOT
nvme0n1p2   50 ГБ  btrfs  /       → ФОРМАТИРУЕТСЯ, метка deskjet
nvme0n1p3  903 ГБ  btrfs  /home   → НЕ ТРОГАЕТСЯ, UUID be7721f1-df08-4875-8b84-562b78cc4536
```

Поэтому NixOS ставится поверх `p1` и `p2`, а `p3` просто подключается.
Не надо гонять полтерабайта туда и обратно: игры (374 ГБ) и Steam (109 ГБ)
остаются на месте. **Вместе с `/home` переезжают сами все настройки**:

- конфиг niri и DankMaterialShell
- SSH-ключи `id_ed25519`, `id_rsa` и `.gnupg`
- профиль Zen, библиотека Steam, VS Code Insiders, ghostty

Файлы на `p3` принадлежат `1000:1000`. UID NixOS выдаст тот же сам, а вот
основной группой по умолчанию сделает `users` (GID 100) — файлы не сломаются,
но группа повиснет числом. Поэтому в конфиге явно `uid = 1000` и группа
`gadjet` с `gid = 1000`.

`/home` — корень раздела, подтомов нет (`subvolid=5`). Опции монтирования
перенесены с Arch: `compress=zstd:3`, `discard=async` — новые файлы сжимаются
так же, как старые.

**Хватит ли 50 ГБ под корень:** там будет весь `/nix/store`. На kitjet он
18 ГБ при 18 поколениях; у deskjet добавятся Steam, LibreOffice, ROCm.
Автоматическая сборка мусора (`nix.gc`, 30 дней) уже в `common.nix`.
Точный размер системы — после сборки, см. ниже.

## Видеокарта RDNA4

RX 9060 XT — свежая архитектура, ей нужно:

| | нужно | в nixpkgs 26.05 |
|---|---|---|
| ядро | ≥ 6.15 | штатное 6.18.49, **zen 7.1.10** |
| Mesa | ≥ 25.1 | 26.1.8 |
| прошивка | `amdgpu/gc_12_0_*` | `linux-firmware-20260810` — **та же версия, что работала на Arch**, 20 файлов `gc_12_0_*` |

Всё с запасом. Ядро — **zen**, как было на Arch: для игровой машины
отзывчивее штатного. RDNA4 поддерживает и штатное 6.18, так что при
проблемах с zen можно откатиться без потерь.

```nix
hardware.amdgpu = {
  initrd.enable = true;       # драйвер в initrd: картинка с первых секунд
  opencl.enable = true;       # ROCm — на Arch стояли rocminfo и amdsmi
  overdrive.enable = true;    # разгон и вентиляторы, нужно для LACT
};
```

Опции amdgpu лежат в `services/hardware/amdgpu.nix`, а не в `hardware/` —
искать там.

## Пакеты: что перенесено с Arch

На Arch — 347 явно установленных пакетов, из них 148 из AUR (почти половина
AUR — отладочные `-debug`). **Переносится то, чем реально пользуешься, а не всё.**
На Arch стояли сразу niri, Hyprland, GNOME и куски KDE с тремя менеджерами
входа (`gdm`, `sddm`, `greetd`) — здесь одно окружение, niri + DMS.

Раскладка:

- **системное** (`hosts/deskjet`) — то, что тянет udev, файрвол, группы:
  Steam, gamescope, gamemode, LACT, wireshark, docker, qmk, kdeconnect, bluetooth,
  VPN-плагины NetworkManager
- **пользовательское** (`home/deskjet.nix`) — остальное по категориям:
  игры, работа, сеть, разработка, общение, медиа, консоль

### Чего нет в nixpkgs и чем заменено

| На Arch | В nixpkgs | Замена |
|---|---|---|
| `portproton` | нет | Lutris, Heroic, ProtonPlus; сам — во flatpak |
| `hiddify` | удалён как заброшенный | **`throne`** |
| `nekobox` | переименован | **`throne`** — его наследник |
| `networkmanager-vpn-plugin-pptp` | нет | PPTP небезопасен, плагин убран |

Ещё доступны прокси-клиенты `clash-verge-rev`, `v2rayn`, `sing-box`.

### Ловушка проверки имён пакетов

Проверять существование пакета через `pkgs ? имя` **недостаточно**:

1. **Заглушки удалённых пакетов.** `hiddify-app` есть как имя, но это `throw`
   с сообщением «removed, since it is unmaintained». `? имя` говорит «есть».
2. **Несвободные пакеты.** Discord, Spotify, TeamSpeak, WinBox, Яндекс Музыка
   падают без `allowUnfree`. Проверка на голом `legacyPackages` даёт ложное «нет»,
   хотя в системе `allowUnfree` включён в `common.nix`.

Правильно — вычислять реальный `drvPath` с тем же `allowUnfree`, что в системе:

```bash
nix eval --impure --raw --expr '
let
  np = (builtins.getFlake "git+file:///home/gadjet/nixos").inputs.nixpkgs;
  p = import np { system = "x86_64-linux"; config.allowUnfree = true; };
  res = n: if !(p ? ${n}) then "НЕТ ${n}" else
           if (builtins.tryEval p.${n}.drvPath).success then "OK  ${n}" else "СЛОМ ${n}";
in builtins.concatStringsSep "\n" (map res [ "throne" "discord" ])'
```

Отсутствующее имя `tryEval` не ловит (это ошибка, а не `throw`), поэтому
сначала `p ? имя`, потом `tryEval`.

## Попутная находка: Jellyfin в общем модуле

`modules/desktop.nix` включал **Jellyfin** — сервис kitjet, который раздаёт
`/tank/media` на телевизор. Модуль общий для всех рабочих столов, так что
deskjet получил бы ненужный медиасервер с открытым портом.

Перенесён в `hosts/kitjet`. Проверено, что для kitjet это чистый перенос:
деривация системы **побайтово та же** до и после.

```bash
nix eval --raw .#nixosConfigurations.kitjet.config.system.build.toplevel.drvPath
```

Хороший приём для любого рефакторинга: если drvPath не изменился —
поведение не изменилось.

## Про «общий конфиг niri» — как это работает на самом деле

Решено: `~/.config/niri/config.kdl` **остаётся обычным файлом**, не под home-manager (правки применяются мгновенно, `niri validate` работает, пересборка не нужна).

Следствие, о котором надо помнить: **«общий конфиг» с kitjet сейчас поддерживается вручную.** Автоматической синхронизации нет, файлы разъедутся, если за этим не следить.

Второе: даже общий конфиг не может быть *идентичным*. kitjet — телевизор (смотришь с дивана: другой `scale`, крупнее шрифты, другие имена выходов), gadnix — монитор на столе. Общей может быть логика (биндинги, правила окон, вид), различаться будут блоки `output`.

> **Вариант на будущее, который снимает этот компромисс:** `config.lib.file.mkOutOfStoreSymlink`. Home-manager делает симлинк на **изменяемый** файл в репозитории, а не копию в `/nix/store`. Файл остаётся редактируемым, правки мгновенные, `niri validate` работает — и при этом он в git и общий для машин. Вернуться, когда конфиг устаканится.


## Установка

### Подготовка — выполнено

- [x] Железо, разделы, UID, опции монтирования сняты с живого Arch
- [x] Прошивка и версии ядра/Mesa для RDNA4 проверены
- [x] Список пакетов снят, перенесён по категориям
- [x] Конфиг `hosts/deskjet/` и `home/deskjet.nix` вычисляется
- [x] Система собрана на kitjet — **20 ГБ** за поколение, в корень 50 ГБ влезает с запасом
- [x] Бэкап на `tank/backup-deskjet` — 192 ГБ передано, 116 ГБ на диске, проверен

### Бэкап

Хоть `/home` и не трогается, одна ошибка в выборе раздела при `mkfs` стоила бы
всего. Копируется всё, кроме того, что перекачивается: игр, Steam и кэша.

```bash
sudo zfs create tank/backup-deskjet
rsync -aHAX --info=progress2 --no-inc-recursive \
  --exclude=/Games --exclude=/.local/share/Steam --exclude=/.cache --exclude=/.steam \
  gadjet@<deskjet>:/home/gadjet/ /tank/backup-deskjet/
```

169 ГБ, гигабит по кабелю, около получаса. ZFS сжимает: из 66 ГБ переданных
на диске легло 29.

Итог: rsync завершился с кодом 23 — «some files were not transferred». Не
скопировалось **6 объектов, все мусор**: `.config/chromium/BrowserMetrics`
(телеметрия) и 5 файлов `.trashinfo` в корзине. Похоже, их создал root, и
пользователю они не читаются.

**Код 23 не повод верить или не верить бэкапу — надо смотреть, что именно.**
Список отказов:

```bash
tr '\r' '\n' < rsync.log | grep -E '^rsync: \[sender\]' | grep -oE '"[^"]+"'
```

И проверка по существу — число файлов в ключевых каталогах совпало до единицы:
Documents 1859, Pictures 530, `.ssh` 8, `.gnupg` 4.

Датасет отдельный — после успешной установки его можно удалить одной
командой `zfs destroy`.
### Сама установка — выполнено (2026-09-12)

- [x] Загрузиться с установщика NixOS
- [x] Форматировать **только** `p1` и `p2` с метками `BOOT` и `deskjet`
- [x] Смонтировать `p3` в `/mnt/home`, **не форматируя**
- [x] Сверить `hardware-configuration.nix` с выводом `nixos-generate-config`
- [x] `nixos-install --flake`

План сработал буквально: `p3` сохранил свой UUID `be7721f1-…`, метки `BOOT`
и `deskjet` на месте, `/home` подхватился со всеми настройками — niri, DMS,
ключи, профиль Zen, библиотека Steam. Ничего не перекачивалось.

Место по факту:

| | размер | занято |
|---|---|---|
| `/boot` (p1) | 1 ГБ | 75 МБ |
| `/` (p2) | 50 ГБ | **13 ГБ**, из них `/nix/store` 21 ГБ (дедуплицирован) |
| `/home` (p3) | 903 ГБ | 529 ГБ |

Оценка «20 ГБ за поколение» подтвердилась: 50 ГБ под корень — с запасом.
Ядро — zen 7.1.10, как и планировалось.

## После установки

### XWayland: Steam не запускался

Первое, на чём споткнулись (2026-09-12). Steam молча закрывался, а в
zenity-окне висело `Unable to open a connection to X`.

Причина: **у niri нет встроенного XWayland.** На Arch его поднимал
`xwayland-satellite`, поставленный отдельно, — при переносе конфига он
потерялся, потому что в `programs.niri.enable` не входит. `DISPLAY` в сессии
был пуст, `/tmp/.X11-unix` пуст, а Steam — чистое X11-приложение.

Лечение — одна строка в `modules/desktop.nix` (модуль общий, kitjet получит
то же самое):

```nix
environment.systemPackages = [ pkgs.xwayland-satellite ];
```

Отдельно прописывать запуск не нужно: niri сам стартует `xwayland-satellite`,
если находит бинарь в `PATH`, и выставляет `DISPLAY` потомкам. После
пересборки в сессии видно `xwayland-satellite :0 -listenfd …` — `-listenfd`
и означает, что процесс запущен композитором, а не руками.

**Принцип:** под Wayland отсутствие X11-приложения выглядит не как «нет
пакета», а как «приложение не стартует». Проверять `echo $DISPLAY` первым
делом.

### Sunshine: сервис поднялся, захват — нет

Включён 2026-09-13 (`services.sunshine` с `capSysAdmin` и `openFirewall`).
Юнит пользовательский, `WantedBy=graphical-session.target`, так что после
`switch` он ждёт следующего входа в сессию — либо `systemctl --user start sunshine`.

Сервис поднялся, но видео не отдавал:

```
Error: [portalgrab] Restore token is not a valid UUID string
Error: [portalgrab] RemoteDesktop CreateSession failed with response code: 2
Fatal: Unable to find display or encoder during startup
```

Две причины, обе от переезда:

1. `~/.config/sunshine/` приехал с Arch вместе с `/home`. В нём лежали
   `capture = portal`, `output_name = 0` и `portal_token` от **другого**
   backend портала — отсюда «not a valid UUID».
2. Портал на niri неполный: `org.gnome.Mutter.ScreenCast` niri реализует
   (её и берёт `xdg-desktop-portal-gnome`), а `org.gnome.Mutter.RemoteDesktop`
   — **нет**. Sunshine же в режиме `portal` идёт именно через RemoteDesktop.

Проверка, кто чем владеет на шине:

```bash
busctl --user status org.gnome.Mutter.ScreenCast     # PID niri
busctl --user status org.gnome.Mutter.RemoteDesktop  # No such device or address
```

Решение — не портал, а `wlr-screencopy`, который niri поддерживает
(`zwlr_screencopy_manager_v1` version 3). В `~/.config/sunshine/sunshine.conf`:

```
capture = wlr
output_name = DP-1     # имя выхода из `niri msg outputs`, было «0» с Arch
```

Плюс убран `portal_token` (сохранён как `portal_token.arch-bak`).
После этого энкодеры нашлись на самой карте:

```
Found H.264 encoder: h264_vaapi [vaapi]
Found HEVC encoder: hevc_vaapi [vaapi]
Found AV1 encoder:  av1_vaapi  [vaapi]
vaapi vendor: Mesa … AMD Radeon RX 9060 XT (radeonsi, gfx1200)
```

Web-интерфейс — https://localhost:47990, порты 47989/47990 слушаются.
`nvenc` пробуется первым и падает на `Cannot load libcuda.so.1` — это
нормально, карта AMD, сообщение информационное.

> **Хвост:** рабочий `sunshine.conf` лежит в `/home`, а не в git. Кандидат —
> `services.sunshine.settings` в `hosts/deskjet`, тогда захват и выход
> описаны декларативно. Не сделано: Web-UI пишет в тот же файл, надо
> решить, кто из них главный.

### Устаревшие опции — вычищены

`nixos-rebuild build --flake .#deskjet` ругался тремя warning'ами;
исправлено 2026-09-13, сборка теперь чистая:

| было | стало | где |
|---|---|---|
| `programs.git.userName` | `programs.git.settings.user.name` | `home/common.nix` |
| `programs.git.userEmail` | `programs.git.settings.user.email` | `home/common.nix` |
| `inherit (final) system` | `inherit (final.stdenv.hostPlatform) system` | `modules/common.nix` |

Оба файла общие, так что kitjet чинится тем же коммитом.

### Осталось

- [x] Проверить Steam и Proton
- [x] Проверить VIA — udev-правила из `hardware.keyboard.qmk.enable`
- [x] Sunshine — включён, захват через `wlr`
- [x] Устаревшие опции в общих модулях
- [x] `switch` на deskjet и на kitjet после общих правок
      (`modules/desktop.nix`, `modules/common.nix`, `home/common.nix`) — 2026-09-13
- [x] Расхождение с `origin/master` сведено
- [x] Вход по ключу с deskjet на kitjet проверен: `ssh kitjet` без пароля
- [ ] Удалить `tank/backup-deskjet`, когда всё проверено

**Про Sunshine решено:** главный — Web-UI. `~/.config/sunshine/sunshine.conf`
правится через интерфейс, в nix переносится только сам факт включения сервиса
(`services.sunshine` в `hosts/deskjet`). Значит, файл живёт в `/home` и в git
не попадает — при переустановке его вернёт раздел `p3`, как вернул в этот раз
(вместе с настройками от Arch, которые и пришлось чинить).

[[00-Проект]] · [[Репозиторий]] · [[kitjet]] · [[Грабли]]
