# M0: what the S24 Ultra (SM-S928B) showed

Measured with `scripts/probe-host.sh` on 2026-11-19, on a phone with One UI 9
(Android 17, SDK 37) and KernelSU. The raw report is not kept here (it lists
the owner's installed apps); this is what it says.

## Host

| | |
|---|---|
| Model / board | SM-S928B, `e3q`, platform `pineapple` (Snapdragon 8 Gen 3 for Galaxy) |
| Kernel | `6.1.162-android14` (GKI), Samsung build `S928BXXU6EZIF`, aarch64 |
| SELinux | Enforcing; the shell's context is `u:r:ksu:s0` |
| Root | KernelSU (`ksud`), with Zygisk, LSPosed and TrickyStore modules present |
| Storage | `/data` f2fs, 222 GB, 34 GB free: room for a guest of a few GB |
| Partitions | dynamic (`super` on `sda33`), one slot (no A/B suffix), `userdata` on `sda46` |
| Binder | binderfs (`/dev/binderfs`, with `/dev/binder`, `hwbinder`, `vndbinder` as links) |

## Kernel options (the list was cut at 60 lines: what is missing is unknown, not absent)

Present: `NAMESPACES`, `NET_NS`, `CGROUPS`, `BRIDGE`, `VETH`, `TUN`, `INPUT_UINPUT`, `UHID`,
`DRM` (+ `DRM_KMS_HELPER`, `DRM_MIPI_DSI`, `DRM_PANEL`), `SND` (+ `SND_SOC`, compress offload),
`KVM`, `MODULES`.

**Not in the list: `PID_NS`, `USER_NS`** (they would sit between `NAMESPACES` and `NET_NS`).
Android kernels leave them off. If that holds, the guest can not be PID 1 of its own
PID namespace: astra's init has to run as an ordinary process that reaps its
children as a subreaper. The mount namespace (which OneOS pivots with) is there.

`DRM_MSM` is not in the list: the display driver is Qualcomm's out-of-tree one.
The runtime has `QIPCRTR` among the socket protocols (the kernel speaks QRTR).

## Display and GPU

- `/dev/dri/card0` and `renderD128` exist: a KMS device (Qualcomm's SDE driver), not a mainline `msm`.
- Connectors: `DSI-1` connected, **1440x3120 at 120 Hz and 80 Hz, command mode**
  (`cmdHS`); `DP-1` not connected; two virtual ones.
- Android runs it at **1080x2340** by default (density 450), with 1440x3120 and 720x1560 as modes.
- Backlight `panel0-backlight`, max 12750.
- GPU: **Adreno 750 through `kgsl-3d0`** (Qualcomm's own driver; no DRM render
  node for the GPU), vendor `libEGL_adreno` / `libGLESv2_adreno`. `/dev/dma_heap/qcom,display`.
- `vendor.qti.hardware.display.composer-service` and `surfaceflinger` run.
  `/dev/fb*` does not exist.

## Input

`sec_touchscreen` (`event7`), `sec_touchpad`, `sec_touchproximity`, **`sec_e-pen`** (`event11`, the S Pen),
`gpio-keys`, `pmic_pwrkey`, `pmic_resin`, `hall`, `sec_vibrator_inputff` (force feedback), sensors as input devices.
All plain evdev, readable as root.

## Audio

- One ALSA card, **`pineapple-mtp-snd-card`**, with about 35 PCM devices (`pcmC0D0p` ... `D34p`).
- It is Qualcomm's ASoC with PAL/AGM: the graphs behind those devices are set up by
  the vendor audio HAL (`android.hardware.audio.service_64`, `secaudiohalaidl`) from calibration data,
  so the guest can not play to those PCMs by itself with a mixer profile as on sweet.
- `audioserver` and `media.aaudio` run, with `aaudio.mmap_policy=2`: an AAudio client can play.

## Modem and radios

- `rild`, `imsd`, `com.sec.imsservice` run; baseband `S928BXXU6EZIF` loaded; **no SIM in the phone** (`ABSENT`).
- `/dev/smd*`, `/dev/at_*` exist; no `/dev/qrtr*` node (QRTR is a socket family).
- `wlan0`, `rmnet_data0..13`, `epdg*`, `p2p0`. Bluetooth: `android.hardware.bluetooth@1.x-impl-qti`.

## Camera, power, the rest

- `/dev/media0-2`, `/dev/video0,1,32,33`; Samsung's camera provider (`vendor.samsung.hardware.camera.provider`) and `camera.unihal`.
- Charging chips `max77775` (charger, fuel gauge), `pca9481`, `sec-direct-charger`, `mfc-charger` (wireless).
- LEDs: `led:flash_0..3`, `led:torch_0..3`, `leds-sec1`, `torch-sec1`; sensors under `/sys/class/sensors`.

## What this changes in docs/ARCHITECTURE.md

1. **Display, first try: take the KMS device.** `card0` is a KMS device, so SysBoard
   could draw on it with Mesa's software rasteriser (`kms_swrast`) if the guest can
   become DRM master: that needs the host's composer service and SurfaceFlinger stopped.
   Whether the SDE driver takes a dumb-buffer commit on a command-mode panel is the question for M2.
   The alternative stays: frames to a SurfaceFlinger layer through `astra-bridge`.
2. **The GPU is not Mesa's `msm` target.** Adreno 750 is behind `kgsl`: GL ES for Qt needs Turnip over KGSL
   with Zink, or the vendor's EGL (bionic) through a bridge. Software first.
3. **Audio goes through AAudio.** One bridge process, bionic, as root, writing PCM from
   PipeWire's sink to an AAudio stream; the microphone the other way.
4. **No PID namespace**, probably: init runs as a subreaper in the host's PID space.
5. **The modem stays with the host's `rild`** until M4 shows that QRTR can be shared: there is no SIM yet to test with.
6. The S Pen and the force-feedback vibrator are ordinary evdev devices: they come cheap.
