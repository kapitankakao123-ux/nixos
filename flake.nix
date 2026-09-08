{
  description = "Домашняя инфраструктура: NixOS на всех машинах";

  # ─────────────────────────────────────────────────────────────
  # INPUTS — ОТКУДА берётся код. Единственное место, где указаны
  # источники и их версии. Точные коммиты — в flake.lock.
  # ─────────────────────────────────────────────────────────────
  inputs = {
    # Основной репозиторий пакетов. nixos-26.05 — стабильная ветка.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Нужен для отдельных свежих пакетов (pkgs.unstable.*) и для rpinix.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager — управление ~/ (дотфайлы, пользовательские пакеты).
    # Ветка ДОЛЖНА совпадать с веткой nixpkgs (26.05 ↔ release-26.05).
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      # "follows" = «используй мой nixpkgs, не тяни свою копию».
      # Без этого в системе окажется два разных nixpkgs → лишние гигабайты.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DankMaterialShell. /stable — стабильный тег; убери его для dev-версии.
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zen Browser
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # ─────────────────────────────────────────────────────────────
  # OUTPUTS — ЧТО этот flake собирает.
  # ─────────────────────────────────────────────────────────────
  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      # ── Хосты объявлены ОДИН раз ──────────────────────────────
      # Добавить машину = дописать сюда строку и создать hosts/<имя>/.
      # Отсюда генерируются nixosConfigurations (и позже — ноды colmena).
      hosts = {
        kitjet = {
          system = "x86_64-linux";
          home = ./home/kitjet.nix;
        };
        rpinix = {
          system = "aarch64-linux";
          home = null;   # Pi5 — сервер без home-manager
        };
        # gadnix = { system = "x86_64-linux"; home = ./home/gadnix.nix; };
      };

      # Сборка одной системы из описания выше.
      mkHost = name: cfg: nixpkgs.lib.nixosSystem {
        inherit (cfg) system;

        # Прокидываем inputs внутрь модулей, чтобы там были доступны
        # inputs.dms и т.п. Без этого модули о flake ничего не знают.
        specialArgs = { inherit inputs; };

        # modules — список кусков конфигурации, они СЛИВАЮТСЯ в один
        # атрибут-сет. Порядок не важен, важна уникальность присваиваний.
        modules = [
          ./hosts/${name}

          # Home Manager как модуль NixOS: ~/ пересобирается той же
          # командой nixos-rebuild, отдельная команда не нужна.
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;    # тот же nixpkgs, что у системы
            home-manager.useUserPackages = true;  # пакеты в /etc/profiles, а не в ~/.nix-profile
            home-manager.backupFileExtension = "hm-bak"; # не падать, если файл уже есть
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.gadjet = cfg.home;
          }
        ];
      };
    in
    {
      nixosConfigurations = nixpkgs.lib.mapAttrs mkHost hosts;

      # TODO: сюда же — ноды colmena из того же hosts, когда появится
      # вторая машина. Пока деплоить нечего: nixos-rebuild локально.
    };
}
