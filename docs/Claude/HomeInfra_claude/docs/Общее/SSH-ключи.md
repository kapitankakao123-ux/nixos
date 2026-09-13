---
tags: [справка, ssh, ключи, безопасность]
---

# SSH-ключи: кто кого пускает

> **Статус на 2026-09-13, вечер: ключей нет нигде.** На deskjet и kitjet
> приватные файлы удалены, агент на deskjet пуст («The agent has no
> identities»). Единственная уцелевшая копия старого ключа — в бэкапе
> на kitjet, `/tank/backup-deskjet/.ssh/id_ed25519`. Вход между машинами
> сейчас только по паролю. Восстановление — в конце заметки.

## Два независимых механизма, которые легко перепутать

**Кого пускают** и **чем заходят** — разные вещи, живут в разных местах.

| | Где лежит | Кто им управляет |
|---|---|---|
| Кого пускать (публичные) | `/etc/ssh/authorized_keys.d/<юзер>` | **NixOS**, из `users.users.gadjet.openssh.authorizedKeys.keys` в `modules/common.nix` |
| Кого пускать (старое) | `~/.ssh/authorized_keys` | руками, переехало с Arch |
| Чем заходить (приватные) | `~/.ssh/id_*` | руками |
| Чем заходить (в памяти) | ssh-agent | сессия, у нас `gnome-keyring` |

sshd на NixOS читает **оба** списка «кого пускать». На deskjet в
`~/.ssh/authorized_keys` лежит только древний RSA `root@CT110` от
Proxmox-контейнера — к нашим машинам отношения не имеет, но и вреда не
делает. Реальный доступ раздаёт `authorized_keys.d`, то есть конфиг.

Отсюда практическое следствие: **удаление чего угодно в `~/.ssh` не
закрывает доступ на машину.** Закрывает — правка `modules/common.nix` + `switch`.

## Разбор случая: ключи удалены, а ssh работает

Все три «странности» объясняются одним и тем же.

**Почему ssh продолжал ходить с deskjet.** Ключи были загружены в агент
до удаления файлов, а удаление файла не выгружает ключ из памяти
работающего агента:

```bash
ssh-add -l
# 256 SHA256:Zsc3CN… gadjet@GadjetArch (ED25519)
# 256 SHA256:/NSsga… gadjet@deskjet    (ED25519)
```

Живёт это ровно до конца сессии. Логаут или ребут — и ключей нет; вытащить
приватную часть из агента нельзя, он её не отдаёт по протоколу. Именно так
и случилось в тот же вечер: `The agent has no identities`.

**Почему пускал GitHub.** Тем же агентским ключом, проверяется так:

```bash
ssh -T -v git@github.com 2>&1 | grep -i "offering\|authenticated"
# debug1: Offering public key: gadjet@GadjetArch … agent
```

Плюс отдельная деталь: `origin` у репозитория — **HTTPS**
(`https://github.com/…/nixos.git`), так что `git fetch/push` ssh вообще не
использует и от удаления ключей не страдает. Ломается только `ssh -T`.

**Почему deskjet пускал сам себя.** Ключ из агента совпал с тем, что NixOS
разложил в `/etc/ssh/authorized_keys.d/gadjet`:

```bash
while read -r k; do echo "$k" > /tmp/k.pub; ssh-keygen -lf /tmp/k.pub; done \
  < /etc/ssh/authorized_keys.d/gadjet
# 256 SHA256:jJyqmd… gadjet@kitjet
# 256 SHA256:Zsc3CN… gadjet@GadjetArch
```

**Почему kitjet НЕ пускало на deskjet.** На kitjet не оказалось ни ключей,
ни агента — предъявлять нечего:

```
debug1: identity file /home/gadjet/.ssh/id_ed25519 type -1   ← и так все шесть
SSH_AUTH_SOCK=                                                ← агента нет
debug1: No more authentication methods to try.
```

Асимметрия именно в этом: на deskjet графическая сессия с `gnome-keyring`
держала агента, на kitjet при входе по ssh агента нет вовсе. `deskjet` при
этом готов принять `gadjet@kitjet` — он записан в `authorized_keys.d`, — но
kitjet не может доказать владение.

## Диагностика: четыре команды

```bash
ssh-add -l                              # что есть в агенте прямо сейчас
ls -l ~/.ssh/id_*                       # что есть на диске
cat /etc/ssh/authorized_keys.d/gadjet   # кого пускает ЭТА машина (из nix)
ssh -v <хост> 2>&1 | grep -iE "identity file|offering|authentications"
```

В выводе `-v` читать так: `type -1` у identity file = файла нет;
`Offering public key … agent` = ключ взят из агента, а не с диска;
`Authentications that can continue: publickey,password` = сервер ещё готов
спросить пароль, то есть не всё потеряно.

## Восстановление

### Вариант 1 — вернуть старый ключ из бэкапа

Старый `gadjet@GadjetArch` уцелел: отпечаток `SHA256:Zsc3CN…` совпадает с
тем, что принимал GitHub. Лежит на kitjet, доступ — по паролю:

```bash
scp kitjet:/tank/backup-deskjet/.ssh/id_ed25519{,.pub} ~/.ssh/
chmod 600 ~/.ssh/id_ed25519
ssh-add ~/.ssh/id_ed25519 && ssh -T git@github.com
```

Ничего в конфиге менять не нужно: публичная часть уже в `modules/common.nix`.

### Вариант 2 — сгенерировать заново (чище)

Ключ носит имя машины, которой больше нет (`GadjetArch`), и лежал в бэкапе
открытым текстом. По-хорошему — новые пары на обеих машинах:

```bash
ssh-keygen -t ed25519 -C gadjet@deskjet        # на deskjet
ssh -t kitjet 'ssh-keygen -t ed25519 -C gadjet@kitjet'   # на kitjet, по паролю
```

Обе публичные части — в `modules/common.nix`, в
`users.users.gadjet.openssh.authorizedKeys.keys`, затем `switch` на **обеих**
машинах. Новую публичку deskjet — ещё и на github.com/settings/keys.

Проверка после этого — обязательно в обе стороны:

```bash
ssh kitjet  true && echo ok   # с deskjet
ssh deskjet true && echo ok   # с kitjet
```

### Правило, из-за которого всё это не стало катастрофой

`PasswordAuthentication = true` в `modules/common.nix` — пока он там, машина
остаётся доступной даже без единого ключа. **Выключать пароли только после
того, как вход по ключу проверен в обе стороны**, иначе первая же такая
чистка отрезает дальнюю машину наглухо и чинится только с клавиатуры.

## Мелочь про имена

`ssh kitjet` работает не из-за DNS: короткие имена подставляет
`programs.ssh.matchBlocks` из `home/common.nix` (`kitjet` → `kitjet.local`,
mDNS). Роутер про короткое имя deskjet до сих пор помнит старую аренду
`GadjetArch.gadjet` — разбор в [[deskjet]].

[[00-Проект]] · [[Грабли]] · [[Репозиторий]] · [[kitjet]] · [[deskjet]]
