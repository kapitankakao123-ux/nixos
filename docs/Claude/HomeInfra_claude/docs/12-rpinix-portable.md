---
tags: [хост, rpinix, pi5, dsi, портативное, дисплей]
---

# rpinix как портативное устройство: DSI-дисплей и оболочка

Переосмысление rpinix: если это Pi5 с 7" DSI-дисплеем, батареями и NVMe, то это не headless-сервер, а **портативное устройство**. Нужны другие компоненты.

## Поддержка DSI-дисплея

### Текущее состояние

Raspberry Pi5 **поддерживает DSI** (Display Serial Interface) в NixOS через:

- **Ядро:** KMS (Kernel Mode Setting) + vc4-kms-dsi драйвер
- **Загрузчик:** U-Boot с overlay для дисплея
- **Device Tree:** наложение (overlay) для привязки дисплея к Pi5

**Стандартный 7" сенсорный дисплей (официальный RPI)** — распознаётся автоматически, если:
1. Включён KMS в конфиге
2. Дисплей подключён правильно (через специальный шлейф на Pi5)

### Конфиг для DSI

В `hosts/rpinix/default.nix`:

```nix
# ── Дисплей ──────────────────────────────────────────
boot.kernelParams = [
  "cma=256M"        # CMA (Contiguous Memory Allocator) для GPU
];

# KMS (Kernel Mode Setting) — обязателен для дисплея
services.xserver.enable = true;
services.xserver.videoDrivers = [ "modesetting" ];

# vc4 (VideoCore IV) — GPU Pi5
hardware.raspberry-pi."5" = {
  enable = true;
  fkms-3d.enable = true;  # 3D ускорение (опционально, жрёт батарею)
};

# Логирование vc4 ошибок
boot.kernelModules = [ "vc4" ];
```

Проверка после загрузки:

```bash
# На Pi5
dmesg | grep -i "vc4\|kms\|dsi"
fbset -s  # показать разрешение дисплея
```

### Сенсор

Стандартный 7" дисплей Pi5 имеет сенсорную панель. Она работает через `evdev` и требует откалибровки. В конфиге:

```nix
services.xserver.libinput = {
  enable = true;
  touchpad.naturalScrolling = false;
};
```

## Выбор оболочки (это критично для батареи!)

### niri + DMS? ❌ НЕТ

Это неправильный выбор для Pi5:

- **Вес:** ~600 МБ в памяти только на окружение
- **Сложность:** Wayland + QML + многоуровневые эффекты
- **Батарея:** сожрёт за час
- **Производительность:** Pi5 будет задыхаться

На Pi5 это буквально тянет систему вниз, как тяжёлый вес на батареях.

### Рекомендуемые варианты

#### 1️⃣ **Sway** (Wayland, лёгкий) ⭐ рекомендуется

Wayland compositor, но без излишеств. Быстро, потребляет ~100-150 МБ памяти:

```nix
# modules/desktop-light.nix (новый модуль для Pi5)
programs.sway = {
  enable = true;
  wrapperFeatures.gtk = true;
};

programs.waybar.enable = true;  # лёгкая панель вместо DMS
xdg.portal.wlr.enable = true;
```

Конфиг простой, быстро запускается, батарея держит 4-6 часов.

#### 2️⃣ **Xfce4** (традиционный DE)

Лёгкий X11 DE, проверен годами:

```nix
desktopManager.xfce.enable = true;
displayManager.lightdm.enable = true;
```

Консервативно, но работает на слабом железе.

#### 3️⃣ **Openbox + Tint2** (минимализм)

Оконный менеджер + лёгкая панель. Максимум контроля, минимум хлама:

```nix
windowManager.openbox.enable = true;
```

Для опытных пользователей.

#### 4️⃣ **Cage (киоск)** — если одно приложение

Если Pi5 только показывает одно окно (браузер, медиа-плеер):

```nix
programs.cage = {
  enable = true;
};
```

Никакой оболочки, только приложение. Идеально для батареи.

### Сравнение

| Оболочка | Память | Батарея | Скорость | Сложность |
| --- | --- | --- | --- | --- |
| niri+DMS | 600+ МБ | ⚠️ ~1-2ч | медленно | сложно |
| **Sway** | 100 МБ | ✅ 4-6ч | быстро | средне |
| Xfce4 | 200 МБ | ✅ 4-5ч | хорошо | просто |
| Openbox | 50 МБ | ✅✅ 6ч+ | отлично | сложно |
| Cage | 20 МБ | ✅✅ 8ч+ | отлично | очень просто |

## Что дальше для Pi5-портатива

### Если Sway выбран

```nix
# hosts/rpinix/default.nix
{
  imports = [
    ../../modules/common.nix
    ../../modules/desktop-light.nix   # Sway + waybar
    ../../modules/container.nix
  ];

  networking.hostName = "rpinix";
  
  # ... остальное как раньше
}
```

### Оптимизация батареи

```nix
# modules/battery-optimization.nix
{
  powerManagement.enable = true;
  
  services.tlp.enable = true;      # управление питанием
  services.thermald.enable = true; # охлаждение
  
  # Отключить ненужное
  services.avahi.enable = false;   # mDNS (ест батарею)
  networking.wireless.iwd.enable = true;  # iwd меньше ест, чем wpa_supplicant
}
```

### Автоматическая блокировка экрана и усыпление

```nix
services.logind = {
  lidSwitch = "suspend";
  powerKey = "suspend";
  powerKeyLongPress = "poweroff";
};

# Отключить дисплей через 5 минут неактивности
environment.etc."systemd/logind.conf.d/screen.conf".text = ''
  [Login]
  IdleAction=lock
  IdleActionSec=300s
'';
```

## Возможные проблемы и решения

**«Дисплей не включается / чёрный экран»**
- Проверить, что шлейф подключён в правильный разъём на Pi5
- Включить КМС и vc4 в конфиге (см. выше)
- `dmesg | grep -i vc4` — искать ошибки

**«Сенсор не работает»**
- Убедиться, что `libinput` включён
- `DISPLAY=:0 xinput list` — должна быть `touchscreen` в списке
- Откалибровать: `xinput_calibrator`

**«Батарея быстро садится»**
- Отключить 3D (убрать `fkms-3d.enable = true`)
- Выключить Wi-Fi, если не нужен: `systemctl stop wpa_supplicant`
- Снизить яркость дисплея
- Выбрать более лёгкую оболочку (Openbox < Sway < Xfce4 < niri+DMS)

**«Нагрев, Pi5 дросселирует ядро»**
- Активировать `services.thermald`
- Использовать корпус с охлаждением (важно для портатива!)
- Снизить CPU частоту (если не критично): `cpufreq-set`

## Рекомендация

**Для Pi5 портатива с батареей:**

1. **Sway** как оболочка (хороший баланс: красиво, быстро, экономно)
2. **Modules/battery-optimization.nix** для оптимизации питания
3. **DSI support** в конфиге ядра (CMA, KMS, vc4)
4. **Контейнеры** для нужных сервисов (если требуются)

Это даст тебе портативное устройство с 4-6 часами батареи и приличной производительностью.

[[00-Проект]] · [[10-kitjet]] · [[11-rpinix]]
