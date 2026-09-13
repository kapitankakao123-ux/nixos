# modules/common.nix — база, которая нужна ЛЮБОЙ машине.
# Nix сам по себе, локаль, время, пользователь, ssh, минимум пакетов.
# Всё, что специфично для конкретного железа или роли — НЕ сюда.
{ config, pkgs, lib, inputs, ... }:

let
  # Публичные ключи машин, с которых разрешён вход. Один список — и для
  # gadjet, и для root, чтобы не разъехались.
  sshKeys = [
    # kitjet: создан 2026-09-11 для установки deskjet через kexec.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPL3eyBKG1xsG/55hY1W8Bt35j+VJjLSxm1CU/FAJfMv gadjet@kitjet"
    # deskjet: ключ пережил переустановку вместе с /home. Подпись в конце
    # осталась от Arch (GadjetArch) — на работу ключа она не влияет.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHMlFT5xnJHR3MgFqzytZjQuhRjC/ZKC1sYaN1cyyATx gadjet@GadjetArch"
  ];
in
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
        inherit (final.stdenv.hostPlatform) system;
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
    # Ключи для входа по ssh — публичные, секретом не являются.
    # Список общий (sshKeys выше): в нём ключи ОБЕИХ машин, чтобы деплоить
    # можно было в любую сторону. Через эти ключи ходит colmena.
    # Пароли (PasswordAuthentication ниже) выключать только после того, как
    # вход по ключу проверен на ОБЕИХ машинах: иначе останешься без доступа
    # к дальней.
    openssh.authorizedKeys.keys = sshKeys;
  };

  # root по ключу — для деплоя с другой машины (nixos-rebuild --target-host,
  # позже colmena: она ходит именно как root). Паролем root не входит —
  # на установленных системах пароль root не задан.
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

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
