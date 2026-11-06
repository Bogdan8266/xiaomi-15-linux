#!/bin/sh
set -e

DIR=/tmp/drm
mkdir -p "$DIR"
cd "$DIR"

echo "=== Loading DRM Stack (33 modules) ==="

MODULES="
qcom_hwspinlock.ko
llcc-qcom.ko
qcom_sysmon.ko
qcom_aoss.ko
qcom_q6v5.ko
qcom_ramdump.ko
mdt_loader.ko
qcom_pil_info.ko
qcom_q6v5_pas.ko
msm_hw_fence.ko
ipclite.ko
synx-driver.ko
msm_ext_display.ko
drm_display_helper.ko
qseecom_proxy.ko
si_core_module.ko
mem_object.ko
smcinvoke_dlkm.ko
hdcp_qseecom_dlkm.ko
gunyah_loader.ko
gh_irq_lend.ko
gh_mem_notifier.ko
altmode-glink.ko
sync_fence.ko
smmu_proxy_dlkm.ko
panel_event_notifier.ko
qcom_va_minidump.ko
msm-mmrm.ko
pm8941-pwrkey.ko
mca_event.ko
mca_log.ko
mca_qcom_panel.ko
msm_drm.ko
"

for mod in $MODULES; do
    echo "<1>[DRM_LOAD] START $mod" > /dev/kmsg 2>/dev/null || true
    echo -n "Loading $mod ... "
    if [ ! -f "$mod" ]; then
        echo "MISSING FILE"
        echo "<1>[DRM_LOAD] MISSING $mod" > /dev/kmsg 2>/dev/null || true
        continue
    fi
    if insmod "$mod" 2>/tmp/insmod_err.txt; then
        echo "OK"
        echo "<1>[DRM_LOAD] OK $mod" > /dev/kmsg 2>/dev/null || true
    else
        err=$(cat /tmp/insmod_err.txt 2>/dev/null)
        echo "FAIL: $err"
        echo "<1>[DRM_LOAD] FAIL $mod: $err" > /dev/kmsg 2>/dev/null || true
        # If synx or msm_drm fails, print details
        if [ "$mod" = "msm_drm.ko" ] || [ "$mod" = "synx-driver.ko" ]; then
            echo "Stopping on critical failure: $mod"
            exit 1
        fi
    fi
    sleep 0.1
done

echo "=== DRM Module Loading Completed ==="
echo "<1>[DRM_LOAD] ALL DONE" > /dev/kmsg 2>/dev/null || true

echo "--- DRM Device Nodes ---"
ls -la /dev/dri /sys/class/drm 2>/dev/null || true
