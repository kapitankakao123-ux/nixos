# hosts/kitjet — кухонный сервер у телевизора, x86_64.
# Здесь только ВЫБОР возможностей (какие modules включены) и то,
# что верно исключительно для этой машины: железо, имя, загрузчик.
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
    ../../modules/storage.nix           # ZFS-пул tank + samba
    ../../modules/virtualisation.nix    # libvirt/KVM для VM образов

    inputs.vscode-server.nixosModules.default
  ];

  networking.hostName = "kitjet";

  # hostId нужен ZFS, чтобы понять, её ли это пул: при импорте он
  # сверяет записанный в пуле hostId с текущим. Уникален на машину,
  # менять нельзя — иначе пул начнёт требовать `zpool import -f`.
  # Значение взято из `head -c 8 /etc/machine-id`.
  networking.hostId = "ab1bac40";

  # ── Загрузка ─────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
   
    # ── VS Code Remote-SSH ───────────────────────────────────
  # Только на kitjet: с deskjet мы ходим на него по ssh и правим конфиги.
  # Служба ждёт появления ~/.vscode-server и патчит распакованные туда
  # бинарники под NixOS. Своих портов не открывает: VS Code уже внутри
  # ssh-туннеля, поэтому в firewall ничего добавлять не нужно.
  services.vscode-server.enable = true;  

  # ── Автовход ─────────────────────────────────────────────
  # Машина стоит у телевизора: после перезагрузки она должна сама
  # оказаться в сессии, а не ждать, пока кто-то дойдёт с клавиатурой.
  #
  # initial_session — это ровно «войти один раз при старте». Греетер
  # (default_session с tuigreet из modules/desktop.nix) никуда не девается:
  # он появится, если из сессии выйти. Поэтому tuigreet не трогаем, а
  # дописываем вторую половину настройки — только здесь, на kitjet.
  # deskjet общий modules/desktop.nix использует тоже, и автовход ему
  # не нужен: там машина за столом.
  #
  # Цена: у gnome-keyring нет пароля, которым он отпирает связку ключей
  # при входе. Если положишь в неё что-то (ssh-ключ с паролем, пароли
  # приложений) — она останется запертой до первого ручного ввода.
  services.greetd.settings.initial_session = {
    command = "niri-session";
    user = "gadjet";
  };

  # boot.kernelPackages здесь НЕ задаётся: ядро выбирает
  # modules/storage.nix, привязывая его к версии ZFS.
  # Вернуть linuxPackages_latest можно только вместе с отказом от ZFS.

  # ── Jellyfin — медиасервер ───────────────────────────────
  # Роль именно этой машины: раздаёт /tank/media на телевизор.
  # Раньше лежал в modules/desktop.nix и приехал бы на любой рабочий
  # стол, включая deskjet. Перенесён сюда 2026-09-11.
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    # Кэш и конфиги — в /var/lib/jellyfin/ (управляется systemd).
    # Медиа-библиотека — в /tank/media (добавляется в веб-интерфейсе).
  };
  
   # ── Контейнеры ───────────────────────────────────────────
  # Декларативно, а не `docker run`: systemd поднимает их сам, они
  # переживают перезагрузку, и «что крутится на машине» видно в git,
  # а не в памяти демона. Правило то же, что и с LXC (см. CLAUDE.md).
  #
  # backend = "docker", потому что docker на kitjet уже включён в
  # modules/virtualisation.nix. Podman сюда не тянем: oci-containers
  # умеет только ОДИН backend на машину.
  virtualisation.oci-containers = {
    backend = "docker";
    containers.pvzge = {
      # PvZ2 Gardendless — браузерная переделка Plants vs Zombies 2.
      # Тег ПРИБИТ намеренно: с `:latest` образ не обновится сам (nix не
      # знает, что тег переехал), зато перестанет быть воспроизводимым —
      # на разных машинах приедет разное. Обновление = правка версии тут.
      image = "docker.io/gaozih/pvzge:v0.14.0";
      # Внутри контейнера обычный веб-сервер на 80.
      ports = [ "8080:80" ];
      autoStart = true;
    };
  };

  # Игра смотрит в локальную сеть: порт нужен открыть руками — у
  # oci-containers своего `openFirewall`, как у jellyfin, нет.
  networking.firewall.allowedTCPPorts = [ 8080 ];

  # ── Kingston SSD для VM образов ────────────────────────────
  # KINGSTON SA400S37480G, 447 GiB, btrfs
  fileSystems."/var/lib/libvirt/images" = {
    device = "/dev/disk/by-uuid/13c0c7da-ad6f-4331-88e9-06948786d0c0";
    fsType = "btrfs";
    options = [ "defaults" "nofail" ];
  };

  # ── Сборка для Pi ────────────────────────────────────────────
  # Позволяет собирать aarch64 прямо здесь (через qemu-user), чтобы не
  # компилировать на самой малине. Раскомментировать перед установкой rpinix.
  # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Маркер формата данных, а не версия ОС. НЕ МЕНЯТЬ НИКОГДА.
  system.stateVersion = "26.05";
}
