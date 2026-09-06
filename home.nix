# home.nix — ПОЛЬЗОВАТЕЛЬ: ~/.config, дотфайлы, прикладные программы.
# Ничего от root. Всё это можно сломать и починить, не трогая загрузку системы.
{ config, pkgs, inputs, ... }:

{
  imports = [
    # Модуль DMS: ставит quickshell, dgop, dms-cli и юниты systemd.
    inputs.dms.homeModules.dank-material-shell
    # Модуль интеграции с niri: генерирует ~/.config/niri/dms/*.kdl
    inputs.dms.homeModules.niri
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

    # Интеграция с niri: модуль кладёт свои куски конфига в
    # ~/.config/niri/dms/{colors,layout,alttab,binds}.kdl
    niri = {
      enableKeybinds = true;    # биндов DMS (Mod+Space — лаунчер, Mod+V — буфер…)
      enableSpawn = true;       # автозапуск `dms run` вместе с niri
    };
  };

  # ── Конфиг niri ─────────────────────────────────────────────
  # Пока пишешь его руками в ~/.config/niri/config.kdl.
  # Обязательно добавь в начало файла:
  #
  #   include "dms/colors.kdl"
  #   include "dms/layout.kdl"
  #   include "dms/alttab.kdl"
  #   include "dms/binds.kdl"
  #
  # Когда конфиг устаканится — положи его в репозиторий и раскомментируй:
  # xdg.configFile."niri/config.kdl".source = ./niri/config.kdl;
  # (после этого файл станет символической ссылкой в /nix/store, т.е.
  #  read-only: правится только через пересборку)

  # ── Пользовательские пакеты ─────────────────────────────────
  home.packages = with pkgs; [
    ghostty            # терминал
    telegram-desktop
    wl-clipboard
    cliphist           # история буфера для DMS
    brightnessctl
    playerctl
    fastfetch
    # winbox4          # MikroTik
    # via              # прошивка/раскладка клавиатуры (GUI-часть)
  ];

  # Пример декларативной программы: home-manager сам генерирует конфиг
  programs.git = {
    enable = true;
    userName = "gadjet";
    userEmail = "kapitankakao123@gmail.com";
  };
}
