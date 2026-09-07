---
tags: [хост, kitjet]
---

# kitjet — кухонный сервер

x86_64. Стоит на кухне, подключён к телевизору. NixOS установлен и работает: niri + DankMaterialShell + ghostty, плюс Obsidian, Zen и Claude Code для работы над этим проектом.

## Роли

- гипервизор (libvirt/KVM)
- файловое хранилище (ZFS + samba/nfs)
- медиа на телевизор (Jellyfin, mpv)
- источник реплик для `rpinix`
- рабочее место, пока `gadnix` и `rpinix` переустанавливаются

## Переезд на структуру репозитория

Сделано (сборка проверена, `nix store diff-closures` показывает только добавленный mpv — остальное побайтово то же, что работало):

- [x] Разложить `~/nixos` по `modules/` + `home/` + `hosts/kitjet/`
- [x] `hardware-configuration.nix` → `hosts/kitjet/` (`git mv`, файл не менялся)
- [x] Старый `configuration.nix` разобран: nix/локаль/юзер/ssh/оверлей → `modules/common.nix`, niri+greetd+portals+шрифты → `modules/desktop.nix`, загрузчик+ядро+hostName+stateVersion → `hosts/kitjet/default.nix`
- [x] `home.nix` → `home/common.nix`, поверх него `home/kitjet.nix` (пока добавляет только mpv)
- [x] `flake.nix`: хосты объявлены один раз в `hosts = { ... }`, `nixosConfigurations` генерируются через `mkHost`
- [x] `system.stateVersion = "26.05"` перенесён без изменений
- [x] Старые `configuration.nix` / `home.nix` / корневой `hardware-configuration.nix` удалены
- [x] `git add -A` — все новые файлы в индексе

Осталось руками:

- [ ] `sudo nixos-rebuild switch --flake ~/nixos#kitjet` (нужен пароль, поэтому не выполнено)
- [ ] Проверить после перезагрузки: греетер, niri, DMS
- [ ] `git commit` — **после** успешной сборки
- [ ] Вписать публичный ssh-ключ в `users.users.gadjet.openssh.authorizedKeys.keys` (`modules/common.nix`) и только потом ставить `PasswordAuthentication = false`. Сейчас пароли по ssh **включены**, как и было
- [ ] `networking.hostId` пока закомментирован — заполнить вместе с включением ZFS

Заметки по переезду:

- Файлы конфига раньше принадлежали `root` (наследство от `/etc/nixos`). Теперь всё в репозитории принадлежит `gadjet` — правится без sudo, sudo нужен только на сам `switch`.
- `modules/storage.nix` и `modules/virtualisation.nix` созданы, но **закомментированы в импортах** `hosts/kitjet/default.nix`. Это сделано намеренно: переезд должен ничего не менять в поведении системы. Включать по одному, по чек-листам ниже.
- Ловушка в `modules/storage.nix`: ZFS — модуль вне дерева ядра, он не собирается с `boot.kernelPackages = linuxPackages_latest`, который сейчас стоит в `hosts/kitjet`. Перед включением ZFS ядро придётся сменить на `config.boot.zfs.package.latestCompatibleLinuxPackages` или убрать переопределение.

## Хранилище

- [ ] Импортировать старый пул: `sudo zpool import -f tank`
- [ ] Раскомментировать `boot.zfs.extraPools = [ "tank" ]` в `modules/storage.nix`
- [ ] Проверить датасеты: `zfs list`
- [ ] Задать пароль samba: `sudo smbpasswd -a gadjet`
- [ ] Проверить доступ с другой машины
- [ ] Убедиться, что `services.zfs.autoScrub` включён

## Виртуализация

- [ ] Раскомментировать мост `br0` в `modules/virtualisation.nix`, подставить своё имя интерфейса (`ip link`)
- [ ] Проверить, что юзер в группах `libvirtd` и `kvm`: `groups`
- [ ] Проверить локально: `virsh list --all`
- [ ] Подключиться с ноутбука: `virt-manager` → `qemu+ssh://gadjet@kitjet.lan/system`
- [ ] Перенести старые qcow2-образы с Proxmox (лежали в `/var/lib/vz/images/`)

## Сборка для Pi

- [ ] Проверить, что `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` работает: `nix build nixpkgs#legacyPackages.aarch64-linux.hello`
- [ ] После этого можно ставить `buildOnTarget = false` для `rpinix` во `flake.nix`

## Медиа

- [ ] Jellyfin поднялся: `http://kitjet.lan:8096`
- [ ] Библиотека смотрит в `/tank/media`
- [ ] Проверить аппаратное декодирование (Jellyfin → Playback → Hardware acceleration)
- [ ] Автологин в niri без ввода пароля, если сервер должен подниматься сам после перезагрузки

## Заметки

- Обновление системы теперь через `nix flake update` + пересборку. Claude Code свои автообновления применить не сможет — в `/nix/store` писать нельзя, это нормально.
- Vault и конфиги лежат в одном каталоге `~/nixos`, чтобы Claude Code видел и то и другое.

[[00-Проект]] · [[01-Репозиторий]] · [[20-Бэкапы]]
