{
  # description — просто человекочитаемая подпись, ни на что не влияет
  description = "NixOS: niri + DankMaterialShell";

  # ─────────────────────────────────────────────────────────────
  # INPUTS — ОТКУДА берётся код. Это единственное место в системе,
  # где указываются источники и их версии.
  # Точные коммиты фиксируются в flake.lock (аналог package-lock.json).
  # ─────────────────────────────────────────────────────────────
  inputs = {
    # Основной репозиторий пакетов. nixos-26.05 — стабильная ветка.
    # Хочешь rolling как в Arch — поменяй на "nixpkgs-unstable".
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

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

    # Пример, как добавляется что-то ещё (Zen Browser нет в nixpkgs):
    # zen-browser = {
    #   url = "github:0xc000022070/zen-browser-flake";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  # ─────────────────────────────────────────────────────────────
  # OUTPUTS — ЧТО этот flake собирает.
  # Аргументы функции = имена из inputs. @inputs — «весь набор целиком»,
  # чтобы пробросить его в модули (используется ниже в specialArgs).
  # ─────────────────────────────────────────────────────────────
  outputs = { self, nixpkgs, home-manager, ... }@inputs: {

    # gadjetarch — имя конфигурации. Обязано совпадать с
    # networking.hostName в configuration.nix (или указывай явно:
    # nixos-rebuild switch --flake .#gadjetarch)
    nixosConfigurations.kitjet = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      # Прокидываем inputs внутрь модулей, чтобы там был доступен
      # inputs.dms и т.п. Без этого модули о flake ничего не знают.
      specialArgs = { inherit inputs; };

      # modules — список кусков конфигурации. Они СЛИВАЮТСЯ в один
      # большой атрибут-сет. Порядок не важен, важна только уникальность
      # присваиваний одной и той же опции.
      modules = [
        ./configuration.nix

        # Подключаем Home Manager как модуль NixOS: тогда ~/ пересобирается
        # той же командой nixos-rebuild, отдельная команда не нужна.
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;    # тот же nixpkgs, что у системы
          home-manager.useUserPackages = true;  # пакеты в /etc/profiles, а не в ~/.nix-profile
          home-manager.backupFileExtension = "hm-bak"; # не падать, если файл уже есть
          home-manager.extraSpecialArgs = { inherit inputs; };

          # Ключ = имя пользователя из configuration.nix
          home-manager.users.gadjet = import ./home.nix;
        }
      ];
    };
  };
}
