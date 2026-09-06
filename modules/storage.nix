# modules/storage.nix — ZFS-хранилище и раздача файлов.
# ПОКА НЕ ИМПОРТИРУЕТСЯ ни одним хостом: kitjet сейчас на btrfs,
# пул tank ещё не импортирован. Порядок включения — в docs/10-kitjet.md.
{ config, pkgs, lib, ... }:

{
  # ── ZFS ──────────────────────────────────────────────────────
  # ВАЖНО: ZFS — модуль ядра вне дерева, он отстаёт от свежих ядер.
  # Вместе с ним нельзя оставлять boot.kernelPackages = linuxPackages_latest,
  # иначе сборка упадёт «zfs not supported on kernel X». Ставить:
  #   boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  # (или просто убрать переопределение ядра в hosts/kitjet).
  boot.supportedFilesystems = [ "zfs" ];

  # Пулы, которые импортируются на старте. Раскомментировать ПОСЛЕ
  # `sudo zpool import -f tank`, иначе система не загрузится.
  # boot.zfs.extraPools = [ "tank" ];

  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  # ── Раздача файлов ───────────────────────────────────────────
  # Пароль samba задаётся императивно: sudo smbpasswd -a gadjet
  # services.samba = {
  #   enable = true;
  #   openFirewall = true;
  #   settings = {
  #     media = {
  #       path = "/tank/media";
  #       "read only" = "no";
  #       "valid users" = "gadjet";
  #     };
  #   };
  # };
}
