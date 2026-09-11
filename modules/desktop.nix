# modules/desktop.nix — графическое рабочее место: niri + DankMaterialShell.
# Системная часть (то, что нужно от root и до логина): композитор, greeter,
# portals, звук, шрифты. Пользовательская часть — в home/common.nix.
# Импортируется на kitjet и deskjet. Здесь только то, что нужно ЛЮБОМУ
# рабочему столу; роли конкретной машины (Jellyfin и т.п.) — в hosts/<имя>.
{ config, pkgs, lib, ... }:

{
  # niri включается системно: ему нужны seat, сессия, portals, polkit.
  # Опция ставит пакет, создаёт niri.desktop и настраивает окружение.
  programs.niri.enable = true;

  # Дисплей-менеджер. tuigreet — минималистичный, в TTY.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
      user = "greeter";
    };
  };

  # Монтирование флешек и внешних дисков из файлового менеджера.
  # Это системная часть: демон + udev-правила + доступ через polkit,
  # поэтому здесь, а не в home. Сам dolphin — в home/common.nix.
  services.udisks2.enable = true;

  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;   # хранилище паролей для приложений

  # Раскладка для X11-приложений через XWayland.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Шрифты — системные, потому что нужны всем приложениям.
  # material-symbols и inter обязательны для DankMaterialShell.
  fonts.packages = with pkgs; [
    inter
    material-symbols
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];

  # Jellyfin отсюда УБРАН (2026-09-11) и перенесён в hosts/kitjet.
  # Этот модуль общий для всех рабочих столов, а медиасервер — роль
  # одного kitjet: он раздаёт /tank/media на телевизор. Здесь Jellyfin
  # приехал бы и на deskjet — вместе с открытым наружу портом.
}
