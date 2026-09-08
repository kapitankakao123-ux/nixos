# modules/desktop-light.nix — Sway (лёгкий Wayland) для портативных устройств.
# Используется на rpinix (Pi5 с DSI-дисплеем + батареи).
# Намного легче niri+DMS: ~100 МБ памяти вместо 600+.
{ config, pkgs, lib, ... }:

{
  # ── Sway ──────────────────────────────────────────────────
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      wl-clipboard
    ];
  };

  # ── Waybar (лёгкая панель вместо DMS) ──────────────────
  programs.waybar.enable = true;

  # ── XDG Portals ────────────────────────────────────────
  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };

  # ── Session для sway ───────────────────────────────────
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.sway}/bin/sway";
      user = "gadjet";
    };
  };

  # ── Шрифты ────────────────────────────────────────────
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
  ];
}
