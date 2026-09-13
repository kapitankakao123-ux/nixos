# modules/storage.nix — ZFS-хранилище и раздача файлов по сети.
# Включается на машинах, у которых есть пул. На kitjet это `tank`.
{ config, pkgs, lib, ... }:

{
  # ── ZFS ──────────────────────────────────────────────────────
  # Ставит модуль ядра и утилиты (zpool, zfs), которых без этого в
  # системе просто нет — именно поэтому «zpool: command not found».
  boot.supportedFilesystems.zfs = true;

  # ВАЖНО: ZFS — модуль вне дерева ядра, он отстаёт от свежих ядер.
  # Поэтому в hosts/kitjet убран boot.kernelPackages = linuxPackages_latest:
  # с ним сборка падает на «zfs not supported on kernel X».
  #
  # Раньше тут стоял `config.boot.zfs.package.latestCompatibleLinuxPackages`.
  # Он объявлен устаревшим и теперь просто указывает на ядро по умолчанию —
  # то есть ровно на `pkgs.linuxPackages`, которое и работает на kitjet (6.18).
  # Пишем явно: то же самое ядро, но без warning'а и без иллюзии, что nixpkgs
  # что-то подбирает за нас. Если ZFS отстанет от дефолтного ядра — пинить
  # конкретный выпуск, например `pkgs.linuxPackages_6_12`.
  boot.kernelPackages = pkgs.linuxPackages;

  # Корень kitjet на btrfs, ZFS-пул `tank` импортируется уже после загрузки,
  # поэтому принудительный импорт корневого пула не нужен. С 26.11 `false`
  # станет дефолтом; ставим явно, чтобы не ловить warning и не менять
  # поведение при обновлении.
  boot.zfs.forceImportRoot = false;

  # Пулы, которые импортируются на старте. Корневая ФС не на ZFS,
  # так что пул подключается уже после загрузки — если он не найдётся,
  # система всё равно поднимется.
  boot.zfs.extraPools = [ "tank" ];

  # Раз в неделю проверять контрольные суммы всех блоков. На зеркале
  # scrub не только находит битые данные, но и лечит их со второй копии.
  services.zfs.autoScrub.enable = true;

  # Следит за состоянием пулов и шлёт события (деградация, ошибки чтения).
  services.zfs.zed.enableMail = false;

  # trim для SSD. На HDD-пуле не делает ничего, но и не мешает —
  # оставлено на случай, если позже добавится SSD-пул.
  services.zfs.trim.enable = true;

  # ── Раздача файлов по сети ───────────────────────────────────
  # Пароль samba задаётся императивно и в конфиг не попадает:
  #   sudo smbpasswd -a gadjet
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "kitjet";
        "security" = "user";
        # Гостей не пускаем: шара только для gadjet по паролю.
        "map to guest" = "never";
      };
      media = {
        path = "/tank/media";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "gadjet";
      };
      files = {
        path = "/tank/files";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "gadjet";
      };
    };
  };

  # Чтобы шара была видна в сетевом окружении Windows (WS-Discovery:
  # старый NetBIOS-браузер в Windows 10/11 отключён).
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
