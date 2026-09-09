{
  description = "Домашняя инфраструктура: NixOS на всех машинах";

  # ─────────────────────────────────────────────────────────────
  # INPUTS — ОТКУДА берётся код. Единственное место, где указаны
  # источники и их версии. Точные коммиты — в flake.lock.
  # ─────────────────────────────────────────────────────────────
  inputs = {
    # Основной репозиторий пакетов. nixos-26.05 — стабильная ветка.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Нужен для отдельных свежих пакетов (pkgs.unstable.*) и ЦЕЛИКОМ для rpinix.
    # Поддержка Pi 5 в installer/sd-card/sd-image-aarch64.nix есть ТОЛЬКО здесь:
    # секции [pi5]/[cm5] в config.txt, bcm2712-*.dtb и общий u-boot.bin
    # (ubootRaspberryPiAarch64). В ветке 26.05 всего этого нет — проверено
    # по исходникам обеих веток 2026-09-09.
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

    # raspberry-pi-nix УБРАН 2026-09-09. Брали его из-за двух утверждений,
    # которые оказались неверны для свежего nixpkgs: якобы нет U-Boot для Pi 5
    # и якобы sd-image-aarch64 не знает про Pi 5. И то и другое есть в unstable.
    # Вдобавок его вендорное ядро запинено на nixpkgs января 2025, тянется из
    # отдельного кэша и стоило нам бага с tpm-crb. Разбор — docs/13-*.md.
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
          home = null;   # Pi5 — пока без home-manager

          # Весь хост собирается из unstable, а не из 26.05. Причина — выше,
          # в комментарии к nixpkgs-unstable: только там sd-image-aarch64
          # умеет Pi 5. Home Manager сюда не подключается (home = null),
          # поэтому расхождение веток 26.05 ↔ unstable ничего не ломает.
          nixpkgs = inputs.nixpkgs-unstable;

          # Штатный сборщик образа из nixpkgs. Он же даёт U-Boot + extlinux,
          # разметку FIRMWARE + корень и расширение корня на первой загрузке.
          extraModules = [
            "${inputs.nixpkgs-unstable}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ];
        };
        # gadnix = { system = "x86_64-linux"; home = ./home/gadnix.nix; };
      };

      # Сборка одной системы из описания выше.
      mkHost = name: cfg:
        let
          # Хост может выбрать свою ветку nixpkgs. Не указал — берётся основная.
          np = cfg.nixpkgs or nixpkgs;
        in
        np.lib.nixosSystem {
          inherit (cfg) system;

          # Прокидываем inputs внутрь модулей, чтобы там были доступны
          # inputs.dms и т.п. Без этого модули о flake ничего не знают.
          specialArgs = { inherit inputs; };

          # modules — список кусков конфигурации, они СЛИВАЮТСЯ в один
          # атрибут-сет. Порядок не важен, важна уникальность присваиваний.
          modules = [
            ./hosts/${name}
          ] ++ (cfg.extraModules or [ ]) ++ (
            # Home Manager только если cfg.home != null (есть пользовательское окружение)
            if cfg.home != null then [
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;    # тот же nixpkgs, что у системы
                home-manager.useUserPackages = true;  # пакеты в /etc/profiles, а не в ~/.nix-profile
                home-manager.backupFileExtension = "hm-bak"; # не падать, если файл уже есть
                home-manager.extraSpecialArgs = { inherit inputs; };
                home-manager.users.gadjet = cfg.home;
              }
            ] else []
          );
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.mapAttrs mkHost hosts;

      # TODO: сюда же — ноды colmena из того же hosts, когда появится
      # вторая машина. Пока деплоить нечего: nixos-rebuild локально.
    };
}
