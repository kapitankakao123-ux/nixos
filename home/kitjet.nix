# home/kitjet.nix — пользовательское окружение именно на kitjet.
# Общее — в home/common.nix, сюда только то, чего нет на других машинах.
{ config, pkgs, inputs, ... }:

{
  imports = [ ./common.nix ];

  home.packages = with pkgs; [
    mpv        # кино на телевизор
  ];
}
