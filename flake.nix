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

        # VS Code Remote-SSH на стороне сервера. Сам VS Code при подключении
    # скачивает свой vscode-server и распаковывает в ~/.vscode-server —
    # обычные бинарники под Ubuntu, которые на NixOS не запускаются
    # (нет /lib64/ld-linux, нет libstdc++ в ожидаемом месте). Модуль ставит
    # службу, которая их патчит после каждой распаковки.
    #
    # Здесь НЕТ `inputs.nixpkgs.follows` — в отличие от соседей выше. У этого
    # flake своего nixpkgs просто нет (только flake-parts), и попытка
    # переопределить несуществующий вход даёт warning:
    #   input 'vscode-server' has an override for a non-existent input 'nixpkgs'
    # Правило простое: follows пишется под входы, которые у зависимости есть.
    vscode-server.url = "github:nix-community/nixos-vscode-server";

    # raspberry-pi-nix УБРАН 2026-09-09. Брали его из-за двух утверждений,
    # которые оказались неверны для свежего nixpkgs: якобы нет U-Boot для Pi 5
    # и якобы sd-image-aarch64 не знает про Pi 5. И то и другое есть в unstable.
    # Вдобавок его вендорное ядро запинено на nixpkgs января 2025, тянется из
    # отдельного кэша и стоило нам бага с tpm-crb. Разбор — vault: Машины/pintu/NixOS-на-Pi5.md.
  };

  # ─────────────────────────────────────────────────────────────
  # OUTPUTS — ЧТО этот flake собирает.
  # ─────────────────────────────────────────────────────────────
  outputs = { self, nixpkgs, home-manager, vscode-server, ... }@inputs:
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

          # Весь хост собирается из unstable, а не из 26.05: только там есть
          # поддержка Pi 5 (ядро с bcm2712, dtb, u-boot для aarch64).
          # Home Manager сюда не подключается (home = null), поэтому
          # расхождение веток 26.05 ↔ unstable ничего не ломает.
          nixpkgs = inputs.nixpkgs-unstable;

          # sd-image БОЛЬШЕ НЕ ПОДКЛЮЧАЕТСЯ. Это обычная установка на диск,
          # а не сборка образа: разметку и загрузчик описывает сам хост.
          # Причина отказа от образа — U-Boot не умеет грузиться с NVMe
          # (boot_targets=mmc usb pxe dhcp, драйвера нет), поэтому /boot
          # живёт на SD, а корень на NVMe. Разбор — vault: Машины/pintu/NixOS-на-Pi5.md.
        };
        # Домашний ПК: игры, браузер, работа. Раньше звался gadnix.
        deskjet = {
          system = "x86_64-linux";
          home = ./home/deskjet.nix;
        };
      };

      # Список модулей одной машины. Общий для nixosConfigurations и colmena,
      # чтобы «что входит в машину» было описано в ОДНОМ месте.
      hostModules = name: cfg:
        [ ./hosts/${name} ] ++ (cfg.extraModules or [ ]) ++ (
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
          ] else [ ]
        );

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
          modules = hostModules name cfg;
        };

      # Машины, которые разворачиваются по сети. rpinix сюда НЕ входит:
      # железо теперь под Ubuntu (см. vault: Машины/pintu), а конфиг оставлен
      # на случай возврата к NixOS.
      deployHosts = nixpkgs.lib.filterAttrs (n: _: n != "rpinix") hosts;
    in
    {
      nixosConfigurations = nixpkgs.lib.mapAttrs mkHost hosts;

      # ── colmena ───────────────────────────────────────────────
      # Разворачивание по сети: собирается ЗДЕСЬ, на целевую машину уезжает
      # готовый результат. Цель указывается явно (deployment.targetHost),
      # поэтому перепутать «собрать для X» и «превратить себя в X» нельзя —
      # в отличие от nixos-rebuild --flake .#X без --target-host.
      #
      #   colmena apply --on deskjet      развернуть на одной машине
      #   colmena apply                   на всех
      #   colmena build                   только собрать, ничего не трогая
      #   colmena apply-local --sudo      на той, за которой сидишь
      colmena = {
        meta = {
          # Базовый набор пакетов для сборки нод.
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
          # Те же specialArgs, что у nixosConfigurations, иначе модули
          # не найдут inputs.dms и упадут на вычислении.
          specialArgs = { inherit inputs; };
        };
      } // nixpkgs.lib.mapAttrs
        (name: cfg: {
          deployment = {
            # Имя .local разрешается через mDNS (avahi в modules/common.nix).
            # Адреса от DHCP у нас уже не раз менялись, поэтому не IP.
            targetHost = "${name}.local";
            targetUser = "root";   # ключ root'а прописан в modules/common.nix
            # Разрешить разворачивать саму себя через apply-local.
            allowLocalDeployment = true;
          };
          imports = hostModules name cfg;
        })
        deployHosts;
    };
}
