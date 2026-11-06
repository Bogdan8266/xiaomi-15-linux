#!/bin/sh
cd /tmp/drm
ok=0; fail=0
if insmod ipclite.ko 2>/tmp/err; then ok=1; echo "OK: ipclite.ko"; else fail=1; echo "FAIL: ipclite.ko: "; fi
if insmod qcom_pil_info.ko 2>/tmp/err; then ok=1; echo "OK: qcom_pil_info.ko"; else fail=1; echo "FAIL: qcom_pil_info.ko: "; fi
if insmod qcom_ramdump.ko 2>/tmp/err; then ok=1; echo "OK: qcom_ramdump.ko"; else fail=1; echo "FAIL: qcom_ramdump.ko: "; fi
if insmod qcom_sysmon.ko 2>/tmp/err; then ok=1; echo "OK: qcom_sysmon.ko"; else fail=1; echo "FAIL: qcom_sysmon.ko: "; fi
if insmod qcom_aoss.ko 2>/tmp/err; then ok=1; echo "OK: qcom_aoss.ko"; else fail=1; echo "FAIL: qcom_aoss.ko: "; fi
if insmod qcom_q6v5.ko 2>/tmp/err; then ok=1; echo "OK: qcom_q6v5.ko"; else fail=1; echo "FAIL: qcom_q6v5.ko: "; fi
if insmod mdt_loader.ko 2>/tmp/err; then ok=1; echo "OK: mdt_loader.ko"; else fail=1; echo "FAIL: mdt_loader.ko: "; fi
if insmod qcom_q6v5_pas.ko 2>/tmp/err; then ok=1; echo "OK: qcom_q6v5_pas.ko"; else fail=1; echo "FAIL: qcom_q6v5_pas.ko: "; fi
if insmod msm_hw_fence.ko 2>/tmp/err; then ok=1; echo "OK: msm_hw_fence.ko"; else fail=1; echo "FAIL: msm_hw_fence.ko: "; fi
if insmod synx-driver.ko 2>/tmp/err; then ok=1; echo "OK: synx-driver.ko"; else fail=1; echo "FAIL: synx-driver.ko: "; fi
if insmod msm-mmrm.ko 2>/tmp/err; then ok=1; echo "OK: msm-mmrm.ko"; else fail=1; echo "FAIL: msm-mmrm.ko: "; fi
if insmod qcom_va_minidump.ko 2>/tmp/err; then ok=1; echo "OK: qcom_va_minidump.ko"; else fail=1; echo "FAIL: qcom_va_minidump.ko: "; fi
if insmod qseecom_proxy.ko 2>/tmp/err; then ok=1; echo "OK: qseecom_proxy.ko"; else fail=1; echo "FAIL: qseecom_proxy.ko: "; fi
if insmod si_core_module.ko 2>/tmp/err; then ok=1; echo "OK: si_core_module.ko"; else fail=1; echo "FAIL: si_core_module.ko: "; fi
if insmod mem_object.ko 2>/tmp/err; then ok=1; echo "OK: mem_object.ko"; else fail=1; echo "FAIL: mem_object.ko: "; fi
if insmod smcinvoke_dlkm.ko 2>/tmp/err; then ok=1; echo "OK: smcinvoke_dlkm.ko"; else fail=1; echo "FAIL: smcinvoke_dlkm.ko: "; fi
if insmod smmu_proxy_dlkm.ko 2>/tmp/err; then ok=1; echo "OK: smmu_proxy_dlkm.ko"; else fail=1; echo "FAIL: smmu_proxy_dlkm.ko: "; fi
if insmod llcc-qcom.ko 2>/tmp/err; then ok=1; echo "OK: llcc-qcom.ko"; else fail=1; echo "FAIL: llcc-qcom.ko: "; fi
if insmod sync_fence.ko 2>/tmp/err; then ok=1; echo "OK: sync_fence.ko"; else fail=1; echo "FAIL: sync_fence.ko: "; fi
if insmod msm_ext_display.ko 2>/tmp/err; then ok=1; echo "OK: msm_ext_display.ko"; else fail=1; echo "FAIL: msm_ext_display.ko: "; fi
if insmod altmode-glink.ko 2>/tmp/err; then ok=1; echo "OK: altmode-glink.ko"; else fail=1; echo "FAIL: altmode-glink.ko: "; fi
if insmod gunyah_loader.ko 2>/tmp/err; then ok=1; echo "OK: gunyah_loader.ko"; else fail=1; echo "FAIL: gunyah_loader.ko: "; fi
if insmod gh_irq_lend.ko 2>/tmp/err; then ok=1; echo "OK: gh_irq_lend.ko"; else fail=1; echo "FAIL: gh_irq_lend.ko: "; fi
if insmod hdcp_qseecom_dlkm.ko 2>/tmp/err; then ok=1; echo "OK: hdcp_qseecom_dlkm.ko"; else fail=1; echo "FAIL: hdcp_qseecom_dlkm.ko: "; fi
if insmod drm_display_helper.ko 2>/tmp/err; then ok=1; echo "OK: drm_display_helper.ko"; else fail=1; echo "FAIL: drm_display_helper.ko: "; fi
if insmod panel_event_notifier.ko 2>/tmp/err; then ok=1; echo "OK: panel_event_notifier.ko"; else fail=1; echo "FAIL: panel_event_notifier.ko: "; fi
if insmod pm8941-pwrkey.ko 2>/tmp/err; then ok=1; echo "OK: pm8941-pwrkey.ko"; else fail=1; echo "FAIL: pm8941-pwrkey.ko: "; fi
if insmod gh_mem_notifier.ko 2>/tmp/err; then ok=1; echo "OK: gh_mem_notifier.ko"; else fail=1; echo "FAIL: gh_mem_notifier.ko: "; fi
if insmod mca_event.ko 2>/tmp/err; then ok=1; echo "OK: mca_event.ko"; else fail=1; echo "FAIL: mca_event.ko: "; fi
if insmod mca_log.ko 2>/tmp/err; then ok=1; echo "OK: mca_log.ko"; else fail=1; echo "FAIL: mca_log.ko: "; fi
if insmod mca_qcom_panel.ko 2>/tmp/err; then ok=1; echo "OK: mca_qcom_panel.ko"; else fail=1; echo "FAIL: mca_qcom_panel.ko: "; fi
if insmod msm_drm.ko 2>/tmp/err; then ok=1; echo "OK: msm_drm.ko"; else fail=1; echo "FAIL: msm_drm.ko: "; fi
echo "Done: ok= fail="
ls -la /dev/dri /dev/graphics /sys/class/drm
