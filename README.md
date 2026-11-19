# astraOS for the Samsung Galaxy S24 Ultra (SM-S928B)

**Design stage. Nothing here boots or runs on the phone yet.**

astraOS can not be flashed onto this phone the way it is onto the Redmi Note 10 Pro
([astra_device_xiaomi_sweet](https://github.com/tsryzenstech/astra_device_xiaomi_sweet)):
the S24 Ultra has no mainline Linux device tree, and writing one needs hardware and
months. The way in is the one [OneOS](https://github.com/tsryzenstech/OneOS) uses for
a second Android: astraOS as a **guest system** on One UI's kernel, on a rooted phone,
started and left from an app, nothing flashed.

What is here:

| | |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | the way in, why, the bridges that have to be built, the milestones M0 to M6, and what this can not give |
| [scripts/probe-host.sh](scripts/probe-host.sh) | reads (and only reads) what the phone has: kernel options, display, input, audio, modem, camera. **Milestone 0: run it and send the report.** |
| [board.conf](board.conf) | the phone's parameters, as for sweet |

```sh
adb push scripts/probe-host.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/probe-host.sh'
adb pull /data/local/tmp/e3q-probe.txt
```

Licence: Apache-2.0, as astraOS.
