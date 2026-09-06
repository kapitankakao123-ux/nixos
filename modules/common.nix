# modules/common.nix — база, которая нужна ЛЮБОЙ машине.
# Nix сам по себе, локаль, время, пользователь, ssh, минимум пакетов.
# Всё, что специфично для конкретного железа или роли — НЕ сюда.
{ config, pkgs, lib, inputs, ... }:

{
  # ── Nix ──────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";  # чистка старых поколений
  };
  nix.optimise.automatic = true;          # дедупликация /nix/store

  nixpkgs.config.allowUnfree = true;

  # Оверлей с unstable: pkgs.unstable.<пакет> доступен в любом модуле
  # и в home-manager (useGlobalPkgs = true отдаёт туда этот же pkgs).
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final) system;
        config.allowUnfree = true;
      };
    })
  ];

  # ── Локаль и время ───────────────────────────────────────────
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ru_RU.UTF-8";
    LC_IDENTIFICATION = "ru_RU.UTF-8";
    LC_MEASUREMENT = "ru_RU.UTF-8";
    LC_MONETARY = "ru_RU.UTF-8";
    LC_NAME = "ru_RU.UTF-8";
    LC_NUMERIC = "ru_RU.UTF-8";
    LC_PAPER = "ru_RU.UTF-8";
    LC_TELEPHONE = "ru_RU.UTF-8";
    LC_TIME = "ru_RU.UTF-8";
  };

  # ── Сеть ─────────────────────────────────────────────────────
  # hostName задаётся в hosts/<имя>/default.nix — он и есть «какая машина».
  networking.networkmanager.enable = true;

  # ── Пользователь ─────────────────────────────────────────────
  users.users.gadjet = {
    isNormalUser = true;
    description = "gadjet";
    extraGroups = [ "networkmanager" "wheel" ];
    # Ключи для входа по ssh. Пока пусто → PasswordAuthentication ниже
    # остаётся включённым. Как впишешь ключ и проверишь вход —
    # выключай пароли (см. комментарий в services.openssh).
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... gadjet@gadnix"
    ];
  };

  # ── SSH ──────────────────────────────────────────────────────
  # Через него ходит colmena, так что сервер нужен на всех машинах.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      # TODO: выключить, когда ключ выше вписан и вход по ключу проверен.
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  # ── Системные пакеты ─────────────────────────────────────────
  # Только то, что нужно ДО логина или из-под root:
  # редактор для аварийной правки конфига, git — иначе flake не соберётся.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
  ];
}
