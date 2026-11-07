# Xiaomi 15 (dada) — Standalone Linux Bringup

Experimental standalone Linux (postmarketOS / Alpine Linux aarch64) port for **Xiaomi 15** (`dada`, Qualcomm Snapdragon 8 Elite / SM8750).

Runs the mobile-friendly **Phosh (Wayland)** environment directly on the hardware with full touchscreen, audio, and Wi-Fi support.

---

##  Current Status

| Component | Status | Notes |
| :--- | :---: | :--- |
| **Display** | ✅ Working | Native OLED panel running at **120 Hz** via `msm_drm` |
| **Touchscreen** | ✅ Working | Synaptics TCM2 (`synaptics_tcm2.ko` + `xiaomi_touch.ko`) |
| **Audio** | ✅ Working | Dual Cirrus Logic CS35L43 amps + WCD9395 codec via PulseAudio |
| **Wi-Fi** | ✅ Working | Qualcomm FastConnect 7900 (`qca_cld3_peach_v2.ko`) |
| **Battery / Power** | ✅ Working | Battery percentage and fuel gauge (`bq27z561.ko` + MCA stack) |
| **Power Button Wake** | ✅ Working | Screen turns off/on without lock-screen freeze via D-Bus daemon |
| **Haptics / Vibration** | ✅ Working | Feedbackd with Qualcomm HV haptics |
| **Apps & Browser** | ✅ Working | Epiphany (GNOME Web) & GNOME Software installed |
| **Android Apps** | 🟡 Ready | Waydroid installed; `binderfs` configured and mounted |
| **Bluetooth** | 🟡 WIP | UART (`/dev/ttyHS0`) and power (`/dev/btpower`) up; needs FastConnect firmware loader |

---

##  Safe Dual-Boot Architecture

This port is **completely non-destructive** to your primary Android / ColorOS / HyperOS installation:
* **Slot A**: Untouched Android OS, user data, and vendor partitions.
* **Slot B**: Dedicated to Linux (`init_boot_b` holds the stage-2 boot ramdisk).
* Vendor and firmware partitions are mounted **strictly read-only (`-o ro`)** at runtime.

---

##  Quick Start

### Prerequisites
* Unlocked bootloader on Xiaomi 15.
* Linux host machine connected via USB with `adb` and `fastboot` installed.
* Stage 2 boot image flashed to `init_boot_b`:
  ```bash
  fastboot flash init_boot_b ksu_stage2_final.img
  ```

### Booting into Linux

1. Reboot to Fastboot and switch to Slot B:
   ```bash
   fastboot set_active b
   fastboot reboot
   ```

2. Launch Phosh Desktop via the host helper:
   ```bash
   ./start_linux.sh
   # or
   python3 boot_linux.py
   ```
   The script automatically serves modules over HTTP (port 8000), connects over USB network (172.16.42.1), and boots Phosh in under 15 seconds.

### Returning to Android

To return to your normal Android system anytime, reboot into Fastboot mode and switch back to Slot A:
```bash
fastboot set_active a
fastboot reboot
```

