# hosts/deskjet — домашний ПК: игры, браузер, работа. x86_64.
# Здесь только ВЫБОР возможностей и то, что верно исключительно для этой
# машины. Рабочий стол (niri + DMS) — общий с kitjet, из modules/desktop.nix.
# Разбор установки — vault: Машины/deskjet/deskjet.md.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    # storage.nix и virtualisation.nix НЕ импортируются: ни ZFS-пула,
    # ни виртуалок на этой машине нет.
  ];

  networking.hostName = "deskjet";

  # ── Загрузка ─────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # /boot всего 1 ГБ, а каждое поколение кладёт туда ядро и initrd
  # (~100 МБ). Без лимита раздел рано или поздно переполнится.
  boot.loader.systemd-boot.configurationLimit = 8;

  # zen — то же ядро, что было на Arch (7.2.3-zen). Для игровой машины
  # отзывчивее штатного. RDNA4 поддерживает и штатное 6.18, так что
  # при проблемах с zen можно вернуться на linuxPackages без потерь.
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ── Видеокарта: Radeon RX 9060 XT (Navi 44, RDNA4) ───────
  # RDNA4 требует ядро ≥ 6.15 и Mesa ≥ 25.1. В nixpkgs 26.05: zen 7.1.10,
  # Mesa 26.1.8 — с запасом. Прошивки gc_12_0_* есть в linux-firmware
  # 20260810 — той же версии, что работала на Arch.
  hardware.enableRedistributableFirmware = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;   # Steam и Proton — 32-битные игры и библиотеки
  };
  hardware.amdgpu = {
    initrd.enable = true;       # драйвер в initrd: картинка с первых секунд, без мигания
    opencl.enable = true;       # вычисления на GPU (ROCm)
    overdrive.enable = true;    # разгон и кривая вентиляторов — нужно для LACT
  };
  services.lact.enable = true;  # управление картой, стоял на Arch

  # ── Пользователь: совпасть с Arch ────────────────────────
  # На p3 все файлы принадлежат 1000:1000. UID NixOS даст тот же сам,
  # а вот основной группой по умолчанию сделает `users` (GID 100) —
  # файлы не сломаются, но группа повиснет числом. Закрепляем явно.
  users.users.gadjet = {
    uid = 1000;
    group = "gadjet";
    shell = pkgs.zsh;           # на Arch была zsh
    extraGroups = [ "video" "render" "input" "wireshark" "docker" ];
  };
  users.groups.gadjet.gid = 1000;
  programs.zsh.enable = true;   # без этого zsh не станет допустимой оболочкой входа

  # ── Игры ─────────────────────────────────────────────────
  # Системные опции, а не пакеты: тянут 32-битные библиотеки,
  # udev-правила контроллеров и правила файрвола.
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;   # отдельная игровая сессия в меню входа
    remotePlay.openFirewall = true;
  };
  programs.gamescope.enable = true;
  programs.gamemode.enable = true;

  # ── Периферия ────────────────────────────────────────────
  hardware.keyboard.qmk.enable = true;   # udev-правила для VIA/QMK
  hardware.bluetooth.enable = true;
  programs.kdeconnect.enable = true;     # ставит пакет и открывает порты

  # ── Работа и сеть ────────────────────────────────────────
  programs.wireshark.enable = true;      # захват без root через группу wireshark
  virtualisation.docker.enable = true;
  # VPN-плагины для NetworkManager — те, что стояли на Arch.
  # PPTP на Arch тоже был, но в nixpkgs его плагина нет: протокол давно
  # считается небезопасным. Если без него никак — только другой клиент.
  networking.networkmanager.plugins = with pkgs; [
    networkmanager-l2tp
    networkmanager-sstp
    networkmanager-strongswan
  ];

  # ── Память ───────────────────────────────────────────────
  # zram как на Arch: сжатый swap в памяти вместо раздела на диске.
  zramSwap.enable = true;

  # ── Sunshine — стриминг игр на Moonlight ─────────────────
  # На Arch стоял, в niri есть рабочие столы Sunshine-1/2/3.
  services.sunshine = {
    enable = true;
    capSysAdmin = true;    # захват экрана через DRM/KMS: без этого под Wayland картинки нет
    openFirewall = true;
    # autoStart ВЫКЛЮЧЕН: запускает его сам niri (`spawn-at-startup "sunshine"`
    # в ~/.config/niri/config.kdl, как было на Arch). Со включённым autoStart
    # стартовало бы два экземпляра, и второй упёрся бы в занятые порты.
    # Когда конфиг niri станет общим с kitjet (dotfiles/), эту строку из него
    # надо убрать, а здесь включить autoStart: Sunshine нужен только deskjet.
    autoStart = false;
  };

  # Маркер формата данных, а не версия ОС. НЕ МЕНЯТЬ НИКОГДА.
  system.stateVersion = "26.05";
}
