# modules/battery-optimization.nix — оптимизация для портативных устройств.
# Для Pi5 с батареей: экономия энергии, управление подсветкой, режимы сна.
{ config, pkgs, lib, ... }:

{
  # ── Управление питанием ────────────────────────────────
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";  # масштабирование частоты по нагрузке
  };

  # ── TLP (расширённое управление питанием) ──────────────
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;  # отключить turbo на батарее
    };
  };

  # ── Thermal (управление тепловыми режимами) ───────────
  services.thermald.enable = true;

  # ── Дополнительные экономии ───────────────────────────
  networking.wireless.iwd.enable = true;  # iwd меньше ест, чем wpa_supplicant

  # Отключить ненужные сервисы на батарее
  services.avahi.enable = false;          # mDNS жрёт батарею
  # services.bluetooth.enable = false;    # если не нужен Bluetooth
}
