#!/bin/sh

echo "[1/7] Bringing up Display (msm_drm.ko)..."
if [ ! -d /sys/class/backlight/panel0-backlight ]; then
    rm -rf /tmp/drm
    mkdir -p /tmp/drm
    wget -q -O - http://172.16.42.2:8000/drm_all.tar.gz | tar -C /tmp/drm -xzf -
    wget -q -O /tmp/load_drm_smart.sh http://172.16.42.2:8000/load_drm_smart.sh
    sh /tmp/load_drm_smart.sh >/dev/null 2>&1 || true
fi
echo 0 > /sys/kernel/debug/dri/0/encoder66/idle_power_collapse 2>/dev/null || true
echo 0 > /sys/class/backlight/panel0-backlight/bl_power 2>/dev/null || true
echo 2200 > /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || true

echo "[2/7] Mounting super partitions (odm, vendor, vendor_dlkm) read-only..."
mdev -s 2>/dev/null || true
mkdir -p /mnt/odm /mnt/vendor /mnt/vendor_dlkm /lib/firmware

mknod /dev/sda34 b 259 18 2>/dev/null || true
mknod /dev/loop0 b 7 0 2>/dev/null || true
mknod /dev/loop1 b 7 8 2>/dev/null || true
mknod /dev/loop2 b 7 16 2>/dev/null || true

losetup -r -o 1048576 /dev/loop0 /dev/sda34 2>/dev/null || true
mount -o ro /dev/loop0 /mnt/odm 2>/dev/null || true

echo "[3/7] Preparing /rootfs..."
mkdir -p /rootfs
if [ ! -f /rootfs/usr/libexec/phosh ]; then
    mount -t tmpfs -o size=3G tmpfs /rootfs 2>/dev/null || true
    wget -q -O - http://172.16.42.2:8000/alpine-phosh-ready.tar.gz | tar -C /rootfs -xzf -
fi
sed -i 's/^root:[^:]*:/root::/' /rootfs/etc/shadow 2>/dev/null || true

mkdir -p /dev/shm /rootfs/proc /rootfs/sys /rootfs/dev /rootfs/dev/pts /rootfs/dev/shm /rootfs/run /rootfs/tmp/xdg
chmod 700 /rootfs/tmp/xdg
mount --bind /proc /rootfs/proc 2>/dev/null || true
mount --bind /sys /rootfs/sys 2>/dev/null || true
mount --bind /dev /rootfs/dev 2>/dev/null || true
mkdir -p /rootfs/dev/pts /rootfs/dev/shm
mount -t devpts -o ptmxmode=666,mode=620 devpts /rootfs/dev/pts 2>/dev/null || true
mount -t tmpfs -o mode=1777 tmpfs /rootfs/dev/shm 2>/dev/null || true
mount -t tmpfs tmpfs /rootfs/run 2>/dev/null || true

mknod -m 666 /dev/null c 1 3 2>/dev/null || true
mknod -m 666 /dev/zero c 1 5 2>/dev/null || true
mknod -m 666 /dev/full c 1 7 2>/dev/null || true
mknod -m 666 /dev/random c 1 8 2>/dev/null || true
mknod -m 666 /dev/urandom c 1 9 2>/dev/null || true
mknod -m 666 /dev/tty c 5 0 2>/dev/null || true
mknod -m 666 /dev/ptmx c 5 2 2>/dev/null || true

mkdir -p /mnt/system_dlkm /mnt/vendor /mnt/vendor_dlkm
mknod /dev/loop3 b 7 24 2>/dev/null || true
chroot /rootfs /usr/bin/python3 -c "
import fcntl, os, struct
for dev, off in [('/dev/loop1', 10193207296), ('/dev/loop2', 10880024576), ('/dev/loop3', 9175040000)]:
    try:
        lfd = os.open(dev, os.O_RDWR)
        bfd = os.open('/dev/sda34', os.O_RDONLY)
        fcntl.ioctl(lfd, 0x4C00, bfd)
        li = bytearray(232)
        struct.pack_into('<Q', li, 24, off)
        struct.pack_into('<I', li, 40, 1)
        fcntl.ioctl(lfd, 0x4C04, li)
        os.close(lfd)
        os.close(bfd)
    except Exception as e:
        pass
" 2>/dev/null || true
mount -o ro /dev/loop1 /mnt/vendor 2>/dev/null || true
mount -o ro /dev/loop2 /mnt/vendor_dlkm 2>/dev/null || true
mount -o ro /dev/loop3 /mnt/system_dlkm 2>/dev/null || true

mkdir -p /mnt/firmware_mnt /mnt/modem_firmware /mnt/dsp /mnt/bt_firmware
for d in sde7 sde8 sde9 sde11; do
    eval $(grep -E "^(MAJOR|MINOR)=" /sys/class/block/$d/uevent)
    [ -b /dev/$d ] || mknod /dev/$d b $MAJOR $MINOR 2>/dev/null || true
done
mount -o ro /dev/sde7 /mnt/firmware_mnt 2>/dev/null || true
mount -o ro /dev/sde8 /mnt/modem_firmware 2>/dev/null || true
mount -o ro /dev/sde11 /mnt/dsp 2>/dev/null || true
mount -o ro /dev/sde9 /mnt/bt_firmware 2>/dev/null || true

ln -sf /mnt/vendor /vendor 2>/dev/null || true
ln -sf /mnt/odm /odm 2>/dev/null || true

mkdir -p /lib/firmware /rootfs/lib/firmware
for src in /mnt/firmware_mnt/image/* /mnt/vendor/firmware/* /mnt/odm/firmware/* /mnt/bt_firmware/image/*; do
    [ -e "$src" ] || continue
    base=$(basename "$src")
    ln -sf "$src" "/lib/firmware/$base" 2>/dev/null || true
    ln -sf "$src" "/rootfs/lib/firmware/$base" 2>/dev/null || true
done
rm -f /lib/firmware/wlan /rootfs/lib/firmware/wlan
for chip in peach peach_v2 kiwi_v2; do
    mkdir -p /lib/firmware/wlan/qca_cld/$chip
    ln -sf /mnt/vendor/etc/wifi/$chip/WCNSS_qcom_cfg.ini /lib/firmware/wlan/qca_cld/$chip/WCNSS_qcom_cfg.ini
    printf "Intf0MacAddress=00037F123456\nIntf1MacAddress=00037F123457\nEND\n" > /lib/firmware/wlan/qca_cld/$chip/wlan_mac.bin
done
ln -sf /lib/firmware/wlan /rootfs/lib/firmware/wlan
rm -f /rootfs/lib/firmware/*.jsn
cp -f /mnt/firmware_mnt/image/*.jsn /rootfs/lib/firmware/ 2>/dev/null || true
ln -sf /rootfs/lib/firmware/regulatory.db /lib/firmware/regulatory.db 2>/dev/null || true
ln -sf /rootfs/lib/firmware/regulatory.db.p7s /lib/firmware/regulatory.db.p7s 2>/dev/null || true
echo -n "/lib/firmware" > /sys/module/firmware_class/parameters/path

echo "[4/7] Loading CPUFreq (4.32 GHz), Touch, Buttons, Haptics, and Battery..."
insmod /lib/modules/qcom_cpucp.ko 2>/dev/null || true
insmod /lib/modules/clk-scmi.ko 2>/dev/null || true
insmod /lib/modules/cpufreq_stats_scmi_v3.ko 2>/dev/null || true
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -f "$p/scaling_governor" ] && echo schedutil > "$p/scaling_governor"
done

insmod /lib/modules/spi-msm-geni.ko 2>/dev/null || true
insmod /lib/modules/i2c-msm-geni.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/xiaomi_touch.ko 2>/dev/null || insmod /lib/modules/xiaomi_touch.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/synaptics_tcm2.ko 2>/dev/null || insmod /lib/modules/synaptics_tcm2.ko 2>/dev/null || true
sleep 1
echo 0 > /sys/class/touch/touch_dev/enable_touch_raw 2>/dev/null || true

insmod /lib/modules/reboot-mode.ko 2>/dev/null || true
insmod /lib/modules/qcom-pon.ko 2>/dev/null || true
insmod /lib/modules/pm8941-pwrkey.ko 2>/dev/null || true

# Load MCA + Fuel Gauge (bq27z561) + Charger + Battery in exact dependency order (NO rmmod!)
for m in \
    qcom_glink.ko qcom_glink_smem.ko qcom_smd.ko rproc_qcom_common.ko \
    qmi_helpers.ko pdr_interface.ko qti_pmic_glink.ko ucsi_qti_glink.ko \
    qti-regmap-debugfs.ko fsa4480-i2c.ko \
    mca_sysfs.ko mca_event.ko mca_log.ko mca_parse_dts.ko \
    mca_platform_buckchg_class.ko mca_platform_cp_class.ko mca_platform_wireless_class.ko \
    mca_strategy_class.ko mca_protocol_class.ko mca_qcom_smem.ko mca_hwid.ko \
    charger_partition.ko mca_protocol_pd_class.ko mca_adsp_glink.ko \
    mca_platform_bc12_class.ko mca_protocol_qc_class.ko mca_qcom_subpmic_proxy.ko \
    qcom-hv-haptics.ko \
    mca_strategy_fg_class.ko mca_common.ko mca_workqueue.ko mca_charge_mievent.ko \
    mca_platform_fg_ic_ops.ko mca_platform_loadsw_class.ko mca_smart_charge.ko \
    bq27z561.ko \
    mca_wireless_revchg.ko mca_lpd_detect.ko mca_connector_antiburn.ko \
    mca_basic_wireless.ko mca_quick_wireless.ko mca_charge_interface.ko \
    mca_strategy_fg_comp.ko \
    mca_business_charger_comp.ko mca_business_battery_comp.ko; do
    if [ -f "/lib/modules/$m" ]; then
        insmod "/lib/modules/$m" 2>/dev/null || true
    elif [ -f "/mnt/vendor_dlkm/lib/modules/$m" ]; then
        insmod "/mnt/vendor_dlkm/lib/modules/$m" 2>/dev/null || true
    fi
done

mkdir -p /dev/input /dev/dri
for ev in /sys/class/input/event*; do
    name=$(basename "$ev")
    majmin=$(cat "$ev/dev" | tr ":" " ")
    mknod "/dev/input/$name" c $majmin 2>/dev/null || true
done

echo "[5/7] Updating fixes and wallpapers..."
mkdir -p /rootfs/tmp /rootfs/usr/share/backgrounds/gnome /rootfs/root/.config/gtk-3.0
chmod 1777 /rootfs/tmp

if [ ! -f /rootfs/usr/lib/libfix_mmap.so ] || [ ! -f /rootfs/usr/bin/pwrkey_wake ]; then
    wget -q -O /rootfs/tmp/fix_mmap.c http://172.16.42.2:8000/fix_mmap.c 2>/dev/null || true
    wget -q -O /rootfs/tmp/fix_vibra.c http://172.16.42.2:8000/fix_vibra.c 2>/dev/null || true
    wget -q -O /rootfs/tmp/backlight_daemon.c http://172.16.42.2:8000/backlight_daemon.c 2>/dev/null || true
    wget -q -O /rootfs/tmp/pwrkey_wake.c http://172.16.42.2:8000/pwrkey_wake.c 2>/dev/null || true
    wget -q -O /rootfs/tmp/bt_power_keeper.c http://172.16.42.2:8000/bt_power_keeper.c 2>/dev/null || true

    chroot /rootfs /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin gcc -shared -fPIC -O2 -o /usr/lib/libfix_mmap.so /tmp/fix_mmap.c -ldl 2>/dev/null || true
    chroot /rootfs /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin gcc -shared -fPIC -O2 -o /usr/lib/libfix_vibra.so /tmp/fix_vibra.c -ldl 2>/dev/null || true
    chroot /rootfs /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin gcc -O2 -o /usr/bin/backlight_daemon /tmp/backlight_daemon.c /usr/lib/libgio-2.0.so.0 /usr/lib/libgobject-2.0.so.0 /usr/lib/libglib-2.0.so.0 2>/dev/null || true
    chroot /rootfs /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin gcc -O2 -o /usr/bin/pwrkey_wake /tmp/pwrkey_wake.c /usr/lib/libgio-2.0.so.0 /usr/lib/libgobject-2.0.so.0 /usr/lib/libglib-2.0.so.0 2>/dev/null || true
    chroot /rootfs /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin gcc -O2 -o /usr/bin/bt_power_keeper /tmp/bt_power_keeper.c 2>/dev/null || true
fi
chmod +x /rootfs/usr/bin/backlight_daemon /rootfs/usr/bin/pwrkey_wake /rootfs/usr/bin/bt_power_keeper 2>/dev/null || true

wget -q -O /rootfs/usr/share/backgrounds/gnome/wallpaper_abstract.jpg http://172.16.42.2:8000/wallpaper_abstract.jpg 2>/dev/null || true
wget -q -O /rootfs/usr/share/backgrounds/gnome/wallpaper_gradient.jpg http://172.16.42.2:8000/wallpaper_gradient.jpg 2>/dev/null || true
wget -q -O /rootfs/usr/share/backgrounds/gnome/wallpaper_night.jpg http://172.16.42.2:8000/wallpaper_night.jpg 2>/dev/null || true
ln -sf /usr/share/backgrounds/gnome/wallpaper_abstract.jpg /rootfs/usr/share/backgrounds/gnome/adwaita-l.jxl 2>/dev/null || true
ln -sf /usr/share/backgrounds/gnome/wallpaper_abstract.jpg /rootfs/usr/share/backgrounds/gnome/adwaita-d.jxl 2>/dev/null || true

cat << "EOF" > /rootfs/root/.config/gtk-3.0/gtk.css
phosh-home,
phosh-overview {
  background-image: linear-gradient(rgba(0, 0, 0, 0.25), rgba(0, 0, 0, 0.35)), url("file:///usr/share/backgrounds/gnome/wallpaper_abstract.jpg");
  background-size: cover;
  background-position: center;
}
phosh-app-grid {
  background-color: rgba(0, 0, 0, 0.30);
}
EOF

grep -q "qcom-hv-haptics" /rootfs/usr/lib/udev/rules.d/90-feedbackd.rules || sed -i '/platform-vibrator/a SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="qcom-hv-haptics", ENV{ID_INPUT}="1", ENV{FEEDBACKD_TYPE}="vibra"' /rootfs/usr/lib/udev/rules.d/90-feedbackd.rules

echo "[6/7] Starting system services, ADSP (remoteproc0), and Wi-Fi (FastConnect 7900)..."
insmod /lib/modules/qrtr.ko 2>/dev/null || true
insmod /lib/modules/qrtr-smd.ko 2>/dev/null || true
insmod /lib/modules/qrtr-tun.ko 2>/dev/null || true

echo none > /sys/bus/platform/devices/4080000.remoteproc-mss/driver_override 2>/dev/null || true
echo none > /sys/bus/platform/devices/32300000.remoteproc-cdsp/driver_override 2>/dev/null || true
echo none > /sys/bus/platform/devices/a3380000.remoteproc-soccp/driver_override 2>/dev/null || true

mkdir -p /rootfs/tmp/tqftpserv
insmod /lib/modules/smp2p.ko 2>/dev/null || true
insmod /lib/modules/smp2p_sleepstate.ko 2>/dev/null || true
sleep 1
chroot /rootfs /usr/bin/tqftpserv </dev/null >/tmp/tqftpserv.log 2>&1 &
chroot /rootfs /usr/bin/pd-mapper </dev/null >/tmp/pd-mapper.log 2>&1 &

insmod /lib/modules/pcie-pdc.ko 2>/dev/null || true
insmod /lib/modules/pci-msm-drv.ko pcie_sm_regs=0x1D07000,0x1040,0x1048,0x3000,0x1 2>/dev/null || true
insmod /lib/modules/mhi.ko 2>/dev/null || true
insmod /lib/modules/qrtr-mhi.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/smem-mailbox.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/cnss_utils.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/cnss_prealloc.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/cnss_plat_ipc_qmi_svc.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/wlan_firmware_service.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/cnss_nl.ko 2>/dev/null || true
insmod /lib/modules/memory_dump_v2.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/cnss2.ko 2>/dev/null || true
sleep 1
[ -e /sys/kernel/cnss/recovery ] && echo 3 > /sys/kernel/cnss/recovery
[ -e /sys/kernel/cnss/fs_ready ] && echo 1 > /sys/kernel/cnss/fs_ready

insmod $(find /mnt/system_dlkm -name "rfkill.ko" | head -n 1) 2>/dev/null || true
insmod /lib/modules/cfg80211.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/gsim.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/rmnet_mem.ko 2>/dev/null || true
insmod /lib/modules/usb_f_gsi.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/ipam.ko 2>/dev/null || true

# Load Audio DSP & Sound Card Stack in verified dependency order
echo "[Audio] Loading ALSA Sound Card stack..."
# 1. Pinctrl & Core QTI audio IPC
for m in pinctrl_lpi_dlkm.ko q6_pdr_dlkm.ko q6_notifier_dlkm.ko snd_event_dlkm.ko \
         gpr_dlkm.ko spf_core_dlkm.ko audio_prm_dlkm.ko q6_dlkm.ko; do
    insmod /mnt/vendor_dlkm/lib/modules/$m 2>/dev/null || true
done

# 2. SoundWire bus & core
for m in swr_dlkm.ko swr_ctrl_dlkm.ko qmp_dlkm.ko; do
    insmod /mnt/vendor_dlkm/lib/modules/$m 2>/dev/null || true
done

# 3. WCD Core (MUST BE BEFORE VA-MACRO for msm-cdc-pinctrl!)
for m in wcd_core_dlkm.ko typec_analog_acc_dlkm.ko wcd9xxx_dlkm.ko; do
    insmod /mnt/vendor_dlkm/lib/modules/$m 2>/dev/null || true
done

# 4. LPASS CDC and Macros (va-macro first so others don't defer!)
for m in lpass_cdc_dlkm.ko lpass_cdc_va_macro_dlkm.ko lpass_cdc_tx_macro_dlkm.ko \
         lpass_cdc_rx_macro_dlkm.ko lpass_cdc_wsa_macro_dlkm.ko lpass_cdc_wsa2_macro_dlkm.ko \
         lpass_bt_swr_dlkm.ko; do
    insmod /mnt/vendor_dlkm/lib/modules/$m 2>/dev/null || true
done

# 5. Codecs & Slaves
for m in mbhc_dlkm.ko wcd939x_slave_dlkm.ko wcd939x_dlkm.ko sdca_registers_dlkm.ko \
         wcd9378_slave_dlkm.ko wcd9378_dlkm.ko wsa883x_dlkm.ko wsa884x_dlkm.ko; do
    insmod /mnt/vendor_dlkm/lib/modules/$m 2>/dev/null || true
done

# 6. Aux audio, Haptics, HDMI/DP, ADSP loader, BT-FM codecs
for m in stub_dlkm.ko swr_haptics_dlkm.ko swr_dmic_dlkm.ko hdmi_dlkm.ko adsp_loader_dlkm.ko \
         audpkt_ion_dlkm.ko audio_pkt_dlkm.ko btfmcodec.ko bt_fm_swr.ko; do
    insmod /mnt/vendor_dlkm/lib/modules/$m 2>/dev/null || true
done
insmod $(find /mnt/system_dlkm -name "snd-soc-hdmi-codec.ko" | head -n 1) 2>/dev/null || true

# 7. Cirrus Smart PA (Xiaomi 15 Speakers!)
insmod /mnt/vendor_dlkm/lib/modules/cs_dsp.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/cs35l43_dlkm.ko 2>/dev/null || true

# 8. Sound Machine Driver
insmod /mnt/vendor_dlkm/lib/modules/machine_dlkm.ko 2>/dev/null || true

sleep 1

mkdir -p /dev/snd /rootfs/dev/snd
for snd_dev in /sys/class/sound/*; do
    [ -d "$snd_dev" ] || continue
    name=$(basename "$snd_dev")
    [ "$name" = "card0" ] && continue
    if [ -f "$snd_dev/dev" ]; then
        majmin=$(cat "$snd_dev/dev" | tr ":" " ")
        mknod "/dev/snd/$name" c $majmin 2>/dev/null || true
        mknod "/rootfs/dev/snd/$name" c $majmin 2>/dev/null || true
    fi
done
chmod 666 /dev/snd/* /rootfs/dev/snd/* 2>/dev/null || true

# Configure Cirrus Smart Amps for Top & Bottom Speakers (Xiaomi 15 hardware profile)
PATH=/usr/bin:/bin:/usr/sbin:/sbin chroot /rootfs sh -c '
amixer -D hw:0 cset name="T ASPRX1 Slot Position" 0 2>/dev/null || true
amixer -D hw:0 cset name="T ASPRX2 Slot Position" 2 2>/dev/null || true
amixer -D hw:0 cset name="T ASPTX Ref" "Ref" 2>/dev/null || true
amixer -D hw:0 cset name="T DSP RX1 Source" "ASPRX1" 2>/dev/null || true
amixer -D hw:0 cset name="T DSP RX2 Source" "ASPRX1" 2>/dev/null || true
amixer -D hw:0 cset name="T PCM Source" DSP 2>/dev/null || true
amixer -D hw:0 cset name="T Amp Gain" 18 2>/dev/null || true
amixer -D hw:0 cset name="T AMP Enable Switch" 1 2>/dev/null || true

amixer -D hw:0 cset name="B ASPRX1 Slot Position" 1 2>/dev/null || true
amixer -D hw:0 cset name="B ASPRX2 Slot Position" 4 2>/dev/null || true
amixer -D hw:0 cset name="B ASPTX Ref" "Ref" 2>/dev/null || true
amixer -D hw:0 cset name="B DSP RX1 Source" "ASPRX1" 2>/dev/null || true
amixer -D hw:0 cset name="B DSP RX2 Source" "ASPRX1" 2>/dev/null || true
amixer -D hw:0 cset name="B PCM Source" DSP 2>/dev/null || true
amixer -D hw:0 cset name="B Amp Gain" 18 2>/dev/null || true
amixer -D hw:0 cset name="B AMP Enable Switch" 1 2>/dev/null || true
' 2>/dev/null || true

# Configure PulseAudio default sink for CS35L43 speakers (hw:0,31)
if ! grep -q "hw:0,31" /rootfs/etc/pulse/default.pa 2>/dev/null; then
    cat << "PA_EOF" >> /rootfs/etc/pulse/default.pa

### Xiaomi 15 CS35L43 Stereo Speakers
load-module module-alsa-sink sink_name=speaker device=hw:0,31
set-default-sink speaker
PA_EOF
fi

# Setup Binder for Waydroid
mkdir -p /dev/binderfs /rootfs/dev/binderfs
mount -t binder binder /dev/binderfs 2>/dev/null || true
mount --bind /dev/binderfs /rootfs/dev/binderfs 2>/dev/null || true
chmod 666 /dev/binderfs/* /rootfs/dev/binderfs/* 2>/dev/null || true
ln -sf /dev/binderfs/binder /dev/binder 2>/dev/null || true
ln -sf /dev/binderfs/hwbinder /dev/hwbinder 2>/dev/null || true
ln -sf /dev/binderfs/vndbinder /dev/vndbinder 2>/dev/null || true
ln -sf /dev/binderfs/binder /rootfs/dev/binder 2>/dev/null || true
ln -sf /dev/binderfs/hwbinder /rootfs/dev/hwbinder 2>/dev/null || true
ln -sf /dev/binderfs/vndbinder /rootfs/dev/vndbinder 2>/dev/null || true

# Setup Bluetooth hardware & power keeper
insmod /mnt/vendor_dlkm/lib/modules/msm_geni_serial.ko 2>/dev/null || true
insmod /mnt/vendor_dlkm/lib/modules/btpower.ko 2>/dev/null || true
mknod /dev/ttyHS0 c 481 0 2>/dev/null || true
mknod /rootfs/dev/ttyHS0 c 481 0 2>/dev/null || true
mknod /dev/btpower c 480 0 2>/dev/null || true
mknod /rootfs/dev/btpower c 480 0 2>/dev/null || true
mknod /dev/rfkill c 10 242 2>/dev/null || true
mknod /rootfs/dev/rfkill c 10 242 2>/dev/null || true
chmod 666 /dev/ttyHS0 /rootfs/dev/ttyHS0 /dev/btpower /rootfs/dev/btpower /dev/rfkill /rootfs/dev/rfkill 2>/dev/null || true
insmod $(find /mnt/system_dlkm -name "bluetooth.ko" | head -n 1) 2>/dev/null || true
insmod $(find /mnt/system_dlkm -name "btbcm.ko" | head -n 1) 2>/dev/null || true
insmod $(find /mnt/system_dlkm -name "btqca.ko" | head -n 1) 2>/dev/null || true
insmod $(find /mnt/system_dlkm -name "hci_uart.ko" | head -n 1) 2>/dev/null || true
/rootfs/usr/sbin/rfkill unblock bluetooth 2>/dev/null || true
chroot /rootfs /usr/bin/bt_power_keeper </dev/null >/tmp/bt_power_keeper.log 2>&1 &

(
    sleep 9
    insmod /mnt/vendor_dlkm/lib/modules/qca_cld3_peach_v2.ko 2>/dev/null || true
) &

# Ensure apk-polkit-server service for GNOME Software
mkdir -p /rootfs/usr/share/dbus-1/system-services
cat << "EOF" > /rootfs/usr/share/dbus-1/system-services/dev.Cogitri.apkPolkit2.service
[D-BUS Service]
Name=dev.Cogitri.apkPolkit2
Exec=/usr/libexec/apk-polkit/apk-polkit-server
User=root
EOF

# Bubblewrap sandbox bypass for WebKitGTK / Epiphany (vendor kernel lacks CONFIG_USER_NS)
if [ ! -f /rootfs/usr/bin/bwrap.orig ]; then
    cp -a /rootfs/usr/bin/bwrap /rootfs/usr/bin/bwrap.orig 2>/dev/null || true
    cat << 'EOF' > /rootfs/usr/bin/bwrap
#!/bin/sh
while [ $# -gt 0 ]; do
    if [ "$1" = "--" ]; then
        shift
        break
    fi
    shift
done
exec "$@"
EOF
    chmod 755 /rootfs/usr/bin/bwrap
fi

mkdir -p /rootfs/etc/profile.d
cat << 'EOF' > /rootfs/etc/profile.d/webkit.sh
export WEBKIT_FORCE_SANDBOX=0
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DMABUF_RENDERER_DISABLE=1
EOF

mkdir -p /rootfs/run/dbus /rootfs/run/wpa_supplicant /rootfs/etc/NetworkManager/conf.d
cat << "EOF" > /rootfs/etc/NetworkManager/conf.d/99-unmanaged.conf
[main]
plugins=keyfile
dhcp=internal
auth-polkit=false

[keyfile]
unmanaged-devices=interface-name:usb*,interface-name:rndis*,interface-name:p2p*,interface-name:wifi-aware*,interface-name:dummy*,interface-name:ifb*,interface-name:sit*,interface-name:tunl*,interface-name:gre*,interface-name:gretap*,interface-name:erspan*,interface-name:ip_vti*,interface-name:ip6*

[device]
wifi.scan-rand-mac-address=no
EOF

rm -f /rootfs/run/dbus/dbus.pid /rootfs/run/elogind.pid
chroot /rootfs /usr/bin/dbus-uuidgen --ensure
chroot /rootfs /usr/bin/dbus-daemon --system --fork 2>/dev/null || true
chroot /rootfs /sbin/udevd --daemon 2>/dev/null || true
chroot /rootfs /bin/udevadm trigger
chroot /rootfs /bin/udevadm settle
chroot /rootfs /usr/libexec/elogind --daemon 2>/dev/null || true
chroot /rootfs /usr/lib/polkit-1/polkitd --no-debug </dev/null >/dev/null 2>&1 &
chroot /rootfs /usr/libexec/upowerd </dev/null >/dev/null 2>&1 &
chroot /rootfs /usr/bin/pwrkey_wake </dev/null >/dev/null 2>&1 &
chroot /rootfs /usr/sbin/wpa_supplicant -u -s -O /run/wpa_supplicant -B 2>/dev/null || true
chroot /rootfs /usr/sbin/NetworkManager 2>/dev/null || true
rm -f /rootfs/run/seatd.sock
chroot /rootfs /usr/bin/env SEATD_VTBOUND=0 /usr/bin/seatd -u root -g root </dev/null >/dev/null 2>&1 &
sleep 1

cat << "EOF" > /rootfs/tmp/phosh_inner.sh
#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export XDG_RUNTIME_DIR=/tmp/xdg
export XDG_CURRENT_DESKTOP=Phosh:GNOME
export XDG_SESSION_DESKTOP=phosh
export XDG_SESSION_TYPE=wayland
export GSK_RENDERER=cairo
export GDK_BACKEND=wayland
export LIBGL_ALWAYS_SOFTWARE=1
export WEBKIT_FORCE_SANDBOX=0
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DMABUF_RENDERER_DISABLE=1
unset LD_PRELOAD

echo 0 > /sys/class/backlight/panel0-backlight/bl_power 2>/dev/null || true
echo 2200 > /sys/class/backlight/panel0-backlight/brightness 2>/dev/null || true
echo 0 > /sys/class/touch/touch_dev/enable_touch_raw 2>/dev/null || true

# Start apk-polkit-server for GNOME Software
/usr/libexec/apk-polkit/apk-polkit-server </dev/null >/dev/null 2>&1 &

# Start PulseAudio daemon and set speaker default sink
pulseaudio -D --exit-idle-time=-1 2>/dev/null || true
pactl set-default-sink speaker 2>/dev/null || true

# Start power key wake daemon
/usr/bin/pwrkey_wake > /tmp/pwrkey_wake.log 2>&1 &

exec dbus-run-session -- sh -c '
    gsettings set org.gnome.desktop.lockdown disable-lock-screen true 2>/dev/null || true
    gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
    gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true 2>/dev/null || true
    gsettings set org.gnome.desktop.interface show-battery-percentage true 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/gnome/wallpaper_abstract.jpg" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri-dark "file:///usr/share/backgrounds/gnome/wallpaper_abstract.jpg" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-options "zoom" 2>/dev/null || true
    gsettings set org.sigxcpu.feedbackd profile "full" 2>/dev/null || true
    LD_PRELOAD=/usr/lib/libfix_vibra.so /usr/libexec/feedbackd > /tmp/feedbackd.log 2>&1 &
    /usr/bin/backlight_daemon > /tmp/backlight_daemon.log 2>&1 &
    /usr/bin/squeekboard > /tmp/squeekboard.log 2>&1 &
    exec /usr/libexec/phosh -U > /tmp/phosh.log 2>&1
'
EOF
chmod +x /rootfs/tmp/phosh_inner.sh

echo "[7/7] Launching Phosh!"
killall -9 phosh phoc squeekboard backlight_daemon gsd-power feedbackd 2>/dev/null || true
chroot /rootfs /usr/bin/env \
    PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root \
    XDG_RUNTIME_DIR=/tmp/xdg \
    WLR_BACKENDS=drm,libinput \
    WLR_DRM_DEVICES=/dev/dri/card0 \
    WLR_RENDERER=pixman \
    WLR_NO_HARDWARE_CURSORS=1 \
    LIBSEAT_BACKEND=seatd \
    SEATD_VTBOUND=0 \
    LD_PRELOAD=/usr/lib/libfix_mmap.so \
    /usr/bin/phoc -S -C /etc/phosh/phoc.ini -E /tmp/phosh_inner.sh </dev/null >/rootfs/tmp/phoc.log 2>&1 &
echo "ALL_PHOSH_READY"
