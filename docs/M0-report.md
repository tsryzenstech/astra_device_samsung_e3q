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

## Round 2 (probe-host2.sh, 2026-11-19)

- **No `PID_NS`, no `USER_NS`**: `IPC_NS`, `UTS_NS`, `TIME_NS`, `NET_NS` are there; the first two are not.
  Confirmed: the guest can not be PID 1. Present: `OVERLAY_FS`, `EROFS_FS`, `EXT4_FS`, `F2FS_FS`, `FUSE_FS`,
  `BLK_DEV_LOOP`, `SECCOMP`, `SECURITY_SELINUX`, `ANDROID_BINDERFS`, `DMABUF_HEAPS`, `SYNC_FILE`, `CGROUP_*`, `MEMCG`,
  netfilter with NAT/MASQUERADE, `BT` (modules), `NFC=m`. No `CONFIG_QRTR` line, no `DRM_MSM`/`MSM_*` lines: Qualcomm's drivers are out of tree.
- **Who has the display**: `vendor.qti.hardware.display.composer-service` (pid of the report: 1838), as `system:graphics`,
  holds `/dev/dri/card0` many times over. The driver is `msm_drm` / `qcom,sde-kms` (`qcom,mdss_mdp@ae00000`),
  DSI controller `ae94000.qcom,mdss_dsi_ctrl0`, a DisplayPort controller `af54000`. The panel is enabled and on.
  The SELinux label of `card0` is `graphics_device`; of the touchscreen `input_device`; of the GPU `gpu_device`.
  No debugfs for DRM.
- **Audio**: `tinymix`, `tinyplay`, `tinycap` exist on the host. The card has **632 controls** and PCMs for `CODEC_DMA-LPAIF_RXTX`
  (RX macros 0 to 6: speaker/earpiece paths), `VA` (digital mics), `MI2S`, `TDM`, `USB_AUDIO`, `SLIM` (Bluetooth),
  `DISPLAY_PORT`, and `cs40l26-pcm` (the haptics amplifier). The routing lives in
  `/vendor/etc/audio/sku_pineapple/mixer_paths_pineapple_mtp.xml` and `resourcemanager_pineapple_mtp.xml`, driven
  by the PAL/AGM HAL: AAudio stays the way in. No `/vendor/etc/acdbdata` (the calibration is elsewhere).
- **Modem**: remoteprocs `adsp`, `mss` (the modem), `cdsp` running, `spss` attached. `persist.radio.multisim.config=dsds`,
  eSIM slot switching present. No SIM inserted.
- **Touch**: `sec_touchscreen` reports multitouch slots up to 9, X and Y 0 to 4095, tracking id up to 65535, pressure 0 to 255
  and `INPUT_PROP_DIRECT`: the coordinates scale 4095 to 1440 and 3120. `sec_e-pen` is a separate evdev device.
- **Processes the host runs**, which a guest has to leave alone: `servicemanager`, `hwservicemanager`, `vndservicemanager`,
  `surfaceflinger`, `system_server`, `zygote64`, `audioserver`, `cameraserver`, `netd`, `vold`, `keystore2`, `gatekeeperd`,
  `rild`, `imsd`, Qualcomm's display, memtrack and perf HALs, Samsung's thermal, light, sysinput, health, vibrator, biometrics,
  security (hermes, vaultkeeper, drk, rtts, proca, fkeymaster) and NFC (`android.hardware.nfc-service.nxp`) services.
- **SELinux** is Enforcing; a root shell can read `/dev/dri/card0`, `/dev/input/event7` and `/dev/kgsl-3d0` as the labels above allow.
  `/data/local/tmp` is `shell_data_file`.
