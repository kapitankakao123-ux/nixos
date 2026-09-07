# home/common.nix — ПОЛЬЗОВАТЕЛЬ: ~/.config, дотфайлы, прикладные программы.
# Одинаково на всех десктопных машинах. Ничего от root:
# это можно сломать и починить, не трогая загрузку системы.
{ config, pkgs, inputs, ... }:

{
  imports = [
    # Модуль DMS: ставит quickshell, dgop, dms-cli и юниты systemd.
    inputs.dms.homeModules.dank-material-shell
  ];

  home.username = "gadjet";
  home.homeDirectory = "/home/gadjet";
  home.stateVersion = "26.05";   # так же не меняется после первой сборки
  programs.home-manager.enable = true;

  # ── DankMaterialShell ───────────────────────────────────────
  programs.dank-material-shell = {
    enable = true;

    systemd = {
      enable = true;            # dms поднимается как user-сервис
      restartIfChanged = true;
    };

    enableSystemMonitoring = true;   # виджеты CPU/RAM (dgop)
    enableVPN = true;
    enableDynamicTheming = true;     # тема из обоев (matugen)
    enableAudioWavelength = true;
    enableCalendarEvents = true;
  };

  # ── Конфиг niri ─────────────────────────────────────────────
  # Намеренно НЕ под управлением home-manager: правится руками в
  # ~/.config/niri/config.kdl, цикл правки — секунды вместо пересборки.
  # В начале файла должно быть:
  #
  #   include "dms/colors.kdl"
  #   include "dms/layout.kdl"
  #   include "dms/alttab.kdl"
  #   include "dms/binds.kdl"

  # ── Пакеты, общие для всех десктопов ────────────────────────
  home.packages = with pkgs; [
    ghostty            # терминал
    telegram-desktop
    wl-clipboard
    cliphist           # история буфера для DMS
    brightnessctl
    playerctl
    fastfetch
    obsidian                                         # unfree, allowUnfree уже включён
    pkgs.unstable.claude-code                        # свежий, из unstable
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default

    # ── Dolphin ───────────────────────────────────────────────
    # Файловый менеджер из KDE. Он здесь, а не в системе: обычное
    # GUI-приложение, root ему не нужен, юнитов и udev-правил не тянет.
    # Единственная его системная часть — udisks2, она в modules/desktop.nix.
    kdePackages.dolphin
    # Спутники. Без них dolphin запустится, но будет заметно куцым —
    # KDE вынесла эти куски в отдельные пакеты, а вне Plasma их никто
    # не подтягивает автоматически.
    kdePackages.kio-extras              # протоколы sftp://, smb://, mtp:// в адресной строке
    kdePackages.kdegraphics-thumbnailers # превью картинок и PDF
    kdePackages.ffmpegthumbs             # превью видео
    kdePackages.breeze-icons             # иконки: вне Plasma темы иконок в системе нет вообще
    kdePackages.kde-cli-tools            # kioclient + обработчик «Открыть с помощью»
    kdePackages.ark                      # архивы: без него в контекстном меню нет «Распаковать»
  ];

  # Dolphin — файловый менеджер по умолчанию: на него уходят клики по
  # папкам из других приложений (xdg-open, «Показать в папке» в браузере).
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = "org.kde.dolphin.desktop";
    };
  };

  # Пример декларативной программы: home-manager сам генерирует конфиг
  programs.git = {
    enable = true;
    userName = "gadjet";
    userEmail = "kapitankakao123@gmail.com";
  };
}
