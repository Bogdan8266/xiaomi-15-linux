#!/bin/sh
echo "=== 1. System Safeguards & Mounts ==="
echo 0 > /proc/sys/kernel/hung_task_timeout_secs 2>/dev/null
echo 0 > /proc/sys/kernel/panic_on_rcu_stall 2>/dev/null
echo 0 > /proc/sys/kernel/panic_on_oops 2>/dev/null
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
mount -t debugfs none /sys/kernel/debug 2>/dev/null

echo "=== 2. Creating Essential Device Nodes ==="
mkdir -p /dev/dri /dev/dma_heap /lib /usr/bin /usr/lib
mknod /dev/dri/card0 c 226 0 2>/dev/null
mknod /dev/dri/renderD128 c 226 128 2>/dev/null
mknod /dev/dma_heap/qcom,display c 248 4 2>/dev/null
mknod /dev/dma_heap/system c 248 1 2>/dev/null
for i in 0 1 2 3 4 5 6 7 8 9; do
    mknod /dev/gpiochip$i c 254 $i 2>/dev/null
    chmod 666 /dev/gpiochip$i 2>/dev/null
done
chmod -R 666 /dev/dri /dev/dma_heap 2>/dev/null

echo "=== 2b. Installing modetest & gpiod tools ==="
wget -q http://172.16.42.2:8000/modetest.tar.gz -O /tmp/modetest.tar.gz
wget -q http://172.16.42.2:8000/gpiod_pkg.tar.gz -O /tmp/gpiod_pkg.tar.gz
tar -xzf /tmp/modetest.tar.gz -C /
mkdir -p /tmp/modetest && tar -xzf /tmp/modetest.tar.gz -C /tmp/modetest
tar -xzf /tmp/gpiod_pkg.tar.gz -C /

cd /tmp/drm || exit 1

echo "=== 3. Loading DRM Pre-requisites ==="

load_mod() {
    mod="$1"
    if [ ! -f "$mod" ]; then
        echo "MISSING: $mod"
        return 1
    fi
    if insmod "$mod" 2>/tmp/insmod.err; then
        echo "OK: $mod"
    else
        err=$(cat /tmp/insmod.err 2>/dev/null)
        echo "FAIL: $mod ($err)"
    fi
}

# Spinlock & Interconnect / Remoteproc
load_mod qcom_hwspinlock.ko
load_mod llcc-qcom.ko
load_mod qcom_sysmon.ko
load_mod qcom_aoss.ko
load_mod qcom_q6v5.ko
load_mod qcom_ramdump.ko
load_mod mdt_loader.ko
load_mod qcom_pil_info.ko
load_mod qcom_q6v5_pas.ko
load_mod msm_hw_fence.ko

# IPC & Synx
load_mod ipclite.ko
load_mod synx-driver.ko

# DRM Helpers & Gunyah / TrustZone
load_mod msm_ext_display.ko
load_mod drm_display_helper.ko
load_mod qseecom_proxy.ko
load_mod si_core_module.ko
load_mod mem_object.ko
load_mod smcinvoke_dlkm.ko
load_mod hdcp_qseecom_dlkm.ko
load_mod gunyah_loader.ko
load_mod gh_irq_lend.ko
load_mod gh_mem_notifier.ko
load_mod altmode-glink.ko
load_mod sync_fence.ko
load_mod smmu_proxy_dlkm.ko
load_mod panel_event_notifier.ko
load_mod qti_amoled_ecm.ko
load_mod qcom_va_minidump.ko
load_mod msm-mmrm.ko
load_mod pm8941-pwrkey.ko

# Xiaomi Panel Driver
load_mod mca_event.ko
load_mod mca_log.ko
load_mod mca_qcom_panel.ko

# QFPROM (required by ae00000.qcom,mdss_mdp ssip_config)
load_mod nvmem_qfprom.ko
load_mod qfprom-sys.ko

echo "=== Prerequisites Loaded. Current lsmod count: $(lsmod | wc -l) ==="

echo "=== 4. Loading msm_drm.ko ==="
insmod msm_drm.ko \
    dsi_display0="qcom,mdss_dsi_o3_42_0d_0a_dsc_cmd:" \
    debugpolicy="32" \
    dumpstate=0 \
    panel_cell_id="AHZ54AR075AL4" \
    oled_wp="031f030002030103" \
    panel_build_id="Pff" 2>/tmp/msm_drm.err

RC=$?
if [ $RC -eq 0 ]; then
    echo "SUCCESS: msm_drm.ko loaded cleanly!"
else
    echo "ERROR ($RC): $(cat /tmp/msm_drm.err)"
fi

echo "=== 5. Checking Display Panel Regulators (GPIO 112 VDDIOLDO 1.8V & GPIO 120 VDDD 1.2V) ==="
cat /sys/kernel/debug/gpio | grep -E '112|120|98|86'

echo "=== 6. Disabling Panel ESD Watchdogs & Idle Power Collapse ==="
echo esd_sw_sim_success > /sys/kernel/debug/qcom,mdss_dsi_o3_42_0d_0a_dsc_cmd/esd_check_mode 2>/dev/null
echo 0 > /sys/kernel/debug/mi_display/esd_sw_prim 2>/dev/null
echo 99999999 > /sys/kernel/debug/dri/0/DSI-1/esd_status_interval 2>/dev/null
echo 0 > /sys/kernel/debug/dri/0/encoder66/idle_power_collapse 2>/dev/null

echo "=== 7. Clearing Continuous Splash State (DPMS 2->1->2 Reset) ==="
timeout 2 /usr/bin/modetest -M msm_drm -s 67@206:#0 -v >/dev/null 2>&1
sleep 1

echo "=== 8. Enabling AMOLED Backlight ==="
echo 0 > /sys/class/backlight/panel0-backlight/bl_power 2>/dev/null
echo 3000 > /sys/class/backlight/panel0-backlight/brightness 2>/dev/null

echo "=== Display Bringup Complete! ==="
ls -la /dev/dri
