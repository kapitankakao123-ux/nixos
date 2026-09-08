# modules/container.nix — контейнеры для rpinix (Podman).
# LXC не используем (см. CLAUDE.md). Вместо него OCI-контейнеры через Podman.
# На Pi5 это эффективнее, чем попытка гипервизации.
{ config, pkgs, lib, ... }:

{
  # ── Podman (Docker-совместимый runtime) ────────────────────
  virtualisation.podman = {
    enable = true;
    # Docker-совместимый сокет: приложения через docker cli будут работать
    dockerSocket.enable = true;
    autoPrune.enable = true;
  };

  # ── OCI-контейнеры (декларативные) ────────────────────────
  # Опиши контейнеры здесь вместо ручного `podman run`.
  # Они будут подняты systemd-юнитами и переживут перезагрузку.
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      # Пример (раскомментировать при наличии контейнера):
      # nginx = {
      #   image = "docker.io/library/nginx:latest";
      #   ports = [ "80:80" "443:443" ];
      #   volumes = [
      #     "/etc/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
      #     "/var/www:/usr/share/nginx/html:ro"
      #   ];
      #   autoStart = true;
      # };
    };
  };
}
