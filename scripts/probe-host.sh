#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Reads what astraOS needs to know about a Galaxy S24 Ultra (SM-S928B, e3q)
# running One UI with root. It only READS: nothing is mounted, written (but the
# report), stopped or started.
#
#   adb push scripts/probe-host.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/probe-host.sh'
#   adb pull /data/local/tmp/e3q-probe.txt
#
# Send e3q-probe.txt back: it decides which of docs/ARCHITECTURE.md's open
# questions are answered and which bridge is built first.

out=/data/local/tmp/e3q-probe.txt
exec > "$out" 2>&1

sec() { echo; echo "=== $1"; }
run() { echo "\$ $*"; "$@" 2>&1 | head -${LINES_MAX:-60}; }

echo "astraOS probe of an e3q host, $(date)"
sec "who"
id
getprop ro.product.model
getprop ro.product.device
getprop ro.board.platform
getprop ro.hardware
getprop ro.build.version.release
getprop ro.build.version.oneui
getprop ro.build.version.sdk
getprop ro.boot.verifiedbootstate
getprop ro.boot.flash.locked
getprop ro.boot.warranty_bit
getprop ro.boot.slot_suffix
getprop ro.boot.dynamic_partitions

sec "kernel"
uname -a
cat /proc/version
zcat /proc/config.gz 2>/dev/null | grep -E "^CONFIG_(NAMESPACES|PID_NS|USER_NS|NET_NS|CGROUPS|BINDER|ANDROID_BINDER|DRM|DRM_MSM|QRTR|QCOM_QMI|FUSE_FS|OVERLAY_FS|SQUASHFS|EXT4_FS|F2FS_FS|SECURITY_SELINUX|DEVTMPFS|TUN|VETH|BRIDGE|MODULES|UHID|INPUT_UINPUT|SND|SND_SOC|USB_GADGET|VIRTIO|KVM)(=|_)"
echo "selinux: $(getenforce 2>&1)"

sec "root"
which su magisk ksud apd 2>/dev/null
ls /data/adb 2>/dev/null | head

sec "partitions"
ls -l /dev/block/by-name 2>/dev/null | head -80
cat /proc/mounts | grep -E "^/dev/(block|mapper)|overlay|tmpfs /(apex|mnt)" | head -40
df -h /data 2>&1

sec "display"
ls -l /dev/dri /dev/fb* /dev/graphics 2>&1 | head
ls /sys/class/drm 2>&1 | head
for c in /sys/class/drm/card*-*; do echo "$c: $(cat $c/status 2>/dev/null) $(cat $c/modes 2>/dev/null | head -2 | tr '\n' ' ')"; done 2>/dev/null
ls /sys/class/graphics 2>&1 | head
ls /sys/class/backlight 2>&1 | head
for b in /sys/class/backlight/*; do echo "$b max=$(cat $b/max_brightness 2>/dev/null) now=$(cat $b/brightness 2>/dev/null)"; done 2>/dev/null
ls -l /dev/kgsl-3d0 /dev/ion /dev/dma_heap 2>&1 | head
getprop ro.surface_flinger.max_frame_buffer_acquired_buffers
dumpsys display 2>/dev/null | grep -E "DisplayDeviceInfo|mBaseDisplayInfo|real [0-9]+ x [0-9]+" | head -5
wm size 2>/dev/null; wm density 2>/dev/null

sec "gpu"
cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null
cat /sys/class/kgsl/kgsl-3d0/devfreq/available_frequencies 2>/dev/null
ls /vendor/lib64/egl /vendor/lib64/hw 2>/dev/null | head -40

sec "input"
cat /proc/bus/input/devices | grep -E "^(N:|P:|H:)" | head -60
ls -l /dev/input 2>&1 | head -20

sec "audio"
cat /proc/asound/cards 2>&1
ls -l /dev/snd 2>&1 | head -30
ls /vendor/lib64/hw 2>/dev/null | grep -i audio
getprop | grep -iE "audio|aaudio" | head -20
ps -A -o PID,NAME 2>/dev/null | grep -iE "audioserver|audiohal|audio.service|pal|agm|vendor.audio" | head

sec "modem"
ls -l /dev/qrtr* /dev/wwan* /dev/smd* /dev/at_* 2>&1 | head
cat /proc/net/protocols 2>/dev/null | grep -i qipcrtr
getprop gsm.version.baseband
getprop gsm.sim.state
getprop ro.telephony.default_network
ps -A -o PID,NAME 2>/dev/null | grep -iE "rild|qcrild|radio|vendor.qti|ims|imsd|cnd" | head -20

sec "radios"
ls /sys/class/net 2>&1
ls /sys/class/bluetooth 2>&1
getprop wifi.interface
ls /vendor/firmware_mnt 2>&1 | head

sec "camera"
ls -l /dev/video* /dev/media* 2>&1 | head -20
ps -A -o PID,NAME 2>/dev/null | grep -iE "camera" | head
dumpsys media.camera 2>/dev/null | grep -E "Device [0-9]+ maps|Camera ID|Resource cost" | head -12

sec "sensors, power, vibration, nfc, fingerprint"
ls /sys/class/power_supply 2>&1
for p in /sys/class/power_supply/*; do echo "$p type=$(cat $p/type 2>/dev/null) cap=$(cat $p/capacity 2>/dev/null) status=$(cat $p/status 2>/dev/null)"; done 2>/dev/null
ls /sys/class/leds 2>&1 | head -30
ls /sys/class/timed_output /sys/class/input/*/device/ff 2>&1 | head -5
ls /dev | grep -iE "nfc|st21|sec_nfc|fingerprint|goodix|ets|vib|haptic|sec_" | head
ls /sys/class/sensors 2>&1 | head

sec "what a guest would have to share"
cat /proc/self/mountinfo | grep -E "/apex|/vendor|/odm|/system_ext|/product" | head -20
ls -ld /dev/binder /dev/hwbinder /dev/vndbinder /dev/binderfs 2>&1
ls /apex 2>/dev/null | head -5
ps -A -o PID,NAME 2>/dev/null | grep -E "surfaceflinger|hwcomposer|composer|zygote|system_server|init$" | head
service list 2>/dev/null | grep -iE "SurfaceFlinger|audio|media.camera|phone|isub" | head -8
lshal 2>/dev/null | grep -E "IComposer|IAudio|IRadio|IPower|ISensors" | head -12

sec "done"
echo "report: $out"
