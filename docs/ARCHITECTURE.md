# astraOS on the Galaxy S24 Ultra (SM-S928B): how it can run, and what is open

**Status: design. Nothing in this repository has run on a phone, and no part of
the phone is known to work from astraOS yet.** This document says what the
way in is, why, which parts have to be built and in which order, and what has to
be measured first (`scripts/probe-host.sh`).

## 1. Two ways in, and the one taken

| | Mainline boot (as on the Redmi Note 10 Pro) | Guest on One UI's kernel (as OneOS) |
|---|---|---|
| Kernel | mainline Linux with a device tree for `e3q` | Samsung's own, the one One UI runs |
| Needs | unlocked bootloader (Knox fuse blown), a boot chain that starts a non-Android image, drivers for the panel, touch, regulators, modem, GPU, audio in mainline | root (KernelSU), a rooted One UI that stays installed |
| Mainline today | SM8650 has boards (MTP, QRD, HDK); the S24 Ultra has none: its panel, touch, PMIC wiring and audio path are not described anywhere upstream | not needed |
| Risk | a phone that does not boot | data of One UI (OneOS's README lists a guest that deleted photos and one that locked the screen hardware) |
| Everything working | months of kernel work per subsystem | what the host's drivers and HALs already do, reached through bridges |

The way in is the second: **astraOS as a guest system next to One UI**, which
is what OneOS does for Android systems ([OneOS](https://github.com/tsryzenstech/OneOS):
`switcher/assets/oneos_switch.sh`, `guest_prepare.sh`, `guest_start.sh`,
`return_to_oneui.sh`). What OneOS shows works on this phone: staging a system
under `/data`, pivoting into it in its own mount namespace, stopping One UI's
zygote (not its HALs), starting the guest, and handing the screen back.

## 2. What is different from OneOS

OneOS's guest is Android: it brings its own zygote and system_server and talks
to the host's vendor HALs the way any Android does. astraOS is not Android and
does not carry Android's frameworks (a standing requirement of the project), so
it has no zygote, no binder client, and its libc is musl. Every service the host
gives through a HAL needs a **bridge**: a small program on the host side (bionic,
built with the NDK) that speaks to the HAL, and a counterpart in the astraOS
guest that looks like a Linux device.

```
 One UI (stopped: zygote, system_server)          astraOS guest (own mount + PID namespace)
 ┌──────────────────────────────────┐             ┌────────────────────────────────────────┐
 │ kernel (Samsung, GKI 6.1)        │  /dev/input │ init (container mode) -> astrad, SysBoard│
 │ vendor HALs: composer, audio,    │◄───────────►│ input: evdev as it is                   │
 │ radio, camera, sensors           │             │                                         │
 │ astra-bridge (bionic, root)      │  sockets    │ display: Wayland client of SysBoard ->   │
 │  display  <- dmabuf/shm frames   │◄───────────►│   frames out; PipeWire sink -> audio out │
 │  audio    <- PCM                 │             │ modem: ModemManager over QRTR (probe)    │
 └──────────────────────────────────┘             └────────────────────────────────────────┘
```

## 3. The parts, in the order they are needed

Each milestone is done when it has run on the phone and the result is written
down in `reports/`. A milestone does not start before the one before is done.

**M0. Measure.** (First round done: [M0-report.md](M0-report.md); second round: `scripts/probe-host2.sh`.) Run `scripts/probe-host.sh` on the rooted phone and send the
report. It decides: whether the kernel has what a container needs (namespaces,
overlay, QRTR), what `/dev/dri` is (Qualcomm's display driver is a KMS device on
recent kernels; the GPU is `kgsl`, not a DRM render node), which input
devices and which audio devices exist, whether the modem is reachable through
QRTR sockets while One UI's radio stack runs, and which SELinux mode the guest
can live with.

**M1. A guest that starts and returns.** astra's init gets a container mode
(second stage only, no first stage, no `super`, no module loading, the host's
`/dev` and `/proc` as they are); the staging, pivot and return scripts are
OneOS's, with astraOS's rootfs as the image and OneOS's guards kept (no mount
added on One UI's partitions, no shared `/data`, FRP and gatekeeper left alone,
SELinux back to enforcing on return). Done when: the phone switches in, runs
astrad headless (a shell over adb), and comes back to One UI with its data intact.

**M2. A picture and touch.** SysBoard needs a display it can draw on.
- *Software first*: Qt with Mesa's `kms_swrast`/llvmpipe on a KMS device, if
  M0 shows the display driver is a KMS device the guest may take, or an offscreen
  SysBoard whose frames `astra-bridge` hands to a SurfaceFlinger layer.
- *Then* Adreno 750: Mesa's Turnip (Vulkan) over `kgsl` with Zink for GL ES.
  This is the piece with the least known: it has to be tried.
- Touch: the touchscreen's evdev device (Samsung's STM/Synaptics driver) read
  directly; the S Pen is another device.

**M3. Sound.** PipeWire's sink writes PCM to `astra-bridge`, which plays it
through AAudio (Qualcomm's audio runs through PAL/AGM, not raw ALSA, so
the guest cannot drive the codec itself). The microphone is the reverse.

**M4. Phone.** ModemManager over QRTR (as on sweet) if the modem is reachable
from the guest at the same time as One UI's radio stack; otherwise the guest
asks the host's radio service through a bridge. Calls and SMS need a SIM, and a
SIM does not work in two systems at once.

**M5. Camera, sensors, battery, charging, Wi-Fi, Bluetooth, NFC, fingerprint.**
Each through the host's service or device. Camera is the hardest (the sensors
are behind Samsung's camera HAL).

**M6. Updates and install.** OTA of the guest image from this repository's
GitHub releases, as for sweet.

## 4. What this cannot give

- A phone that boots straight into astraOS: the host stays One UI.
- Anything without root and an unlocked bootloader.
- "Everything working": it is the sum of M2 to M5, and each is a bridge that
  does not exist yet.

## 5. Safety

OneOS's own warning applies to anything here: switching replaces core parts of a
running system as root. Before the first switch on a phone: back up, remove
the screen lock, and use a phone that can be reset. The switch scripts of M1
will refuse to run without a recent backup marker and will undo what they did
if anything they check goes wrong.
