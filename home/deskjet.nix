# home/deskjet.nix — пользовательское окружение домашнего ПК.
# Общее (терминал, браузеры, Obsidian, VS Code, Dolphin) — в home/common.nix,
# сюда только то, чего нет на других машинах.
#
# Список собран по `pacman -Qqe` с Arch (347 пакетов, из них 148 AUR,
# почти половина AUR — отладочные `-debug`). Перенесено то, чем реально
# пользуешься, а не всё подряд: на Arch стояли сразу niri, Hyprland и GNOME
# с тремя менеджерами входа — здесь одно окружение, niri + DMS.
# Полный исходный список — vault: Машины/deskjet/deskjet.md.
{ config, pkgs, inputs, ... }:

{
  imports = [ ./common.nix ];

  home.packages = with pkgs; [
    # ── Игры ─────────────────────────────────────────────
    # Сам Steam, gamescope и gamemode — системные, в hosts/deskjet.
    lutris
    heroic               # Epic, GOG, Amazon
    protonplus           # версии Proton-GE и Wine-GE
    protontricks
    winetricks
    mangohud             # оверлей FPS
    vkbasalt             # постобработка Vulkan
    dualsensectl         # геймпад DualSense
    antimicrox           # геймпад → клавиатура и мышь
    # portproton — в nixpkgs НЕТ. Закрывается Lutris/Heroic/ProtonPlus;
    # если нужен именно он — есть во flatpak.

    # ── Работа ───────────────────────────────────────────
    # remmina (RDP) — в home/common.nix: нужен на обеих машинах.
    winbox4              # MikroTik, нативный, без wine
    libreoffice-fresh

    # ── Сеть ─────────────────────────────────────────────
    # wireshark — системный (группа для захвата без root), в hosts/deskjet.
    nmap
    iperf3
    # Прокси-клиент. На Arch стояли hiddify и nekobox. hiddify-app из nixpkgs
    # удалён как заброшенный, а nekoray переименован в throne — его и берём,
    # он закрывает оба сценария. Есть ещё: clash-verge-rev, v2rayn, sing-box.
    v2rayn
    xray

    # ── Разработка ───────────────────────────────────────
    gh                   # github-cli
    lazygit
    neovim

    # ── Общение ──────────────────────────────────────────
    discord
    teamspeak6-client

    # ── Медиа ────────────────────────────────────────────
    spotify
    spicetify-cli
    yandex-music
    mpv
    easyeffects          # эквалайзер и обработка звука
    gpu-screen-recorder
    songrec              # распознавание музыки

    # ── Удалённый доступ и обмен ─────────────────────────
    rustdesk
    localsend

    # ── Периферия ────────────────────────────────────────
    via                  # раскладка клавиатуры; udev — системный qmk в hosts/deskjet
    android-tools        # adb, fastboot

    # ── Консоль ──────────────────────────────────────────
    bat
    fd
    fzf
    zoxide
    yazi
    tmux
    htop
    yt-dlp
    transmission_4-gtk
  ];
}
