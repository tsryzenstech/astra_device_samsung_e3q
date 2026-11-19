#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# M0, second round: what the first report left open (docs/M0-report.md). It only
# READS, like probe-host.sh.
#
#   adb push scripts/probe-host2.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/probe-host2.sh'
#   adb pull /data/local/tmp/e3q-probe2.txt

out=/data/local/tmp/e3q-probe2.txt
exec > "$out" 2>&1
sec() { echo; echo "=== $1"; }

echo "astraOS probe 2 of an e3q host, $(date)"

sec "kernel options (all that matter, no cut)"
zcat /proc/config.gz 2>/dev/null | grep -E "^CONFIG_(PID_NS|USER_NS|UTS_NS|IPC_NS|TIME_NS|OVERLAY_FS|FUSE_FS|SQUASHFS|EROFS_FS|EXT4_FS|F2FS_FS|SECURITY_SELINUX|SECCOMP|CGROUP_[A-Z_]+|MEMCG|DEVTMPFS|TMPFS_POSIX_ACL|POSIX_MQUEUE|SYSVIPC|QRTR[A-Z_]*|QCOM_QMI[A-Z_]*|RPMSG[A-Z_]*|DRM_MSM|MSM_[A-Z_]*|QCOM_KGSL|ION|DMABUF_HEAPS[A-Z_]*|DMA_SHARED_BUFFER|SYNC_FILE|SW_SYNC|SND_SOC_[A-Z0-9_]*|BINDER[A-Z_]*|ANDROID_[A-Z_]*|UINPUT|INPUT_EVDEV|V4L2[A-Z_]*|VIDEO_[A-Z_]*|CHARGER[A-Z_0-9]*|CFG80211|MAC80211|NF_TABLES|NETFILTER_XT[A-Z_]*|IP_NF[A-Z_]*|BT[A-Z_]*|NFC[A-Z_]*|CRYPTO_[A-Z0-9_]*FSCRYPT|FS_ENCRYPTION|BLK_INLINE_ENCRYPTION|DM_[A-Z_]*|LOOP[A-Z_]*|BLK_DEV_LOOP)(=|$)" | sort

sec "who owns the display"
ls -l /proc/*/fd 2>/dev/null | grep -E "/dev/dri/card0" | head -10
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  if ls -l /proc/$p/fd 2>/dev/null | grep -q "/dev/dri/card0"; then echo "$p $(cat /proc/$p/cmdline 2>/dev/null | tr '\0' ' ' | cut -c1-80)"; fi
done | head -10
cat /sys/class/drm/card0-DSI-1/enabled /sys/class/drm/card0-DSI-1/dpms 2>&1
ls /sys/kernel/debug/dri 2>&1 | head
cat /sys/kernel/debug/dri/0/state 2>&1 | head -60
ls /sys/class/drm/card0/device 2>&1 | head -20
cat /sys/class/drm/card0/device/uevent 2>&1 | head

sec "drm capabilities from userspace"
for b in modetest drm_info; do which $b 2>/dev/null; done
dumpsys SurfaceFlinger 2>/dev/null | grep -E "composer|HWC|Display [0-9]+ HWC|colorMode|HDR|vsync|refresh" | head -20
service list 2>/dev/null | grep -iE "composer|display" | head
lshal 2>/dev/null | grep -iE "composer|allocator|mapper" | head

sec "audio: mixer, graphs"
cat /proc/asound/pcm 2>&1 | head -60
ls /vendor/etc/audio* /vendor/etc/audio/* 2>&1 | head -40
ls /vendor/etc/acdbdata /vendor/etc/audio_policy_configuration*.xml 2>&1 | head
which tinymix tinyplay tinycap 2>&1
tinymix 2>/dev/null | head -5
cat /vendor/etc/audio/sku_pineapple/audio_policy_configuration.xml 2>/dev/null | head -5
getprop | grep -E "ro.vendor.audio|vendor.audio|persist.vendor.audio" | head -30

sec "modem: QRTR"
cat /proc/net/qrtr 2>&1 | head
ls /dev/subsys* /sys/class/remoteproc 2>&1 | head
for r in /sys/class/remoteproc/remoteproc*; do echo "$r $(cat $r/name 2>/dev/null) $(cat $r/state 2>/dev/null)"; done 2>/dev/null
getprop | grep -E "^\[(ro|persist).*(radio|ril|telephony)" | head -20

sec "touch and pen: capabilities"
for e in event7 event11; do echo "-- $e"; cat /sys/class/input/$e/device/name; cat /sys/class/input/$e/device/capabilities/abs 2>/dev/null; done
getevent -p /dev/input/event7 2>/dev/null | head -30

sec "processes to stop or leave alone (names only)"
ps -A -o NAME 2>/dev/null | grep -E "^(init|zygote|zygote64|surfaceflinger|system_server|audioserver|cameraserver|rild|imsd|netd|vold|keystore2|gatekeeperd|servicemanager|hwservicemanager|vndservicemanager|android\.hardware\.[a-z.]+|vendor\.[a-z.-]+)" | sort -u | head -80

sec "selinux: what a root shell can do"
getenforce
cat /sys/fs/selinux/enforce 2>&1
ls -Z /data/local/tmp 2>&1 | head -3
ls -dZ /data /data/local/tmp /dev/dri/card0 /dev/input/event7 /dev/kgsl-3d0 2>&1

sec "done"
echo "report: $out"
