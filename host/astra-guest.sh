#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Starts and stops astraOS as a guest on a rooted phone (docs/ARCHITECTURE.md, M1).
# Run as root. Milestone 1 is a headless guest: nothing of the host is stopped,
# the screen stays One UI's.
#
#   astra-guest.sh start      mounts the images in a mount namespace of its own and runs init
#   astra-guest.sh stop       asks init to end (SIGTERM), waits, and checks the host
#   astra-guest.sh status
#   astra-guest.sh shell      a shell inside the running guest (needs nsenter)
#
# What lives where ($GUEST_DIR, /data/astra-guest by default):
#   system.img product.img vendor.img   the guest's partitions (scripts/extract-guest.py, make-vendor.sh)
#   data/                               the guest's /data
#   guest.log guest.pid                 the log, and the pid of the launcher
#
# Everything the guest mounts is mounted INSIDE its own mount namespace, which ends with it:
# One UI's mounts are not touched. The guest's /dev is a tmpfs with only the nodes listed
# in DEV_NODES, made as nodes of their own (never bind mounts of the host's): rc files
# chown and chmod /dev nodes, and that must not reach One UI's. Before and after, the
# host's mounts are compared and any difference is reported.

GUEST_DIR=${GUEST_DIR:-/data/astra-guest}
# The nodes the guest sees in /dev (M1: only what a headless guest needs). Later milestones add
# dri/card0, input/event*, kgsl-3d0, snd/*.
DEV_NODES=${DEV_NODES:-"null zero full random urandom tty"}
MIN_FREE_MB=${MIN_FREE_MB:-1200}

say() { echo "astra-guest: $*"; }
die() { echo "astra-guest: $*" >&2; exit 1; }

host_mounts() { sed 's/^[0-9]* [0-9]* //' /proc/self/mountinfo | sort | md5sum | cut -d' ' -f1; }

running() {
    [ -s "$GUEST_DIR/guest.pid" ] && kill -0 "$(cat "$GUEST_DIR/guest.pid")" 2>/dev/null
}

free_mb() { df -k "$GUEST_DIR" | awk 'NR==2 { print int($4 / 1024) }'; }

case "$1" in
start)
    [ "$(id -u)" = 0 ] || die "run as root"
    running && die "the guest already runs (pid $(cat "$GUEST_DIR/guest.pid"))"
    for i in system product vendor; do
        [ -s "$GUEST_DIR/$i.img" ] || die "$GUEST_DIR/$i.img is missing"
    done
    mkdir -p "$GUEST_DIR/data" || die "cannot create $GUEST_DIR/data"
    [ "$(free_mb)" -ge "$MIN_FREE_MB" ] || die "less than $MIN_FREE_MB MB free in $GUEST_DIR"
    before=$(host_mounts)
    echo "$before" > "$GUEST_DIR/host-mounts.before"
    : > "$GUEST_DIR/guest.log"
    # A new mount namespace; its mounts are private (nothing leaks to the host's, nothing of
    # the host's changes under it).
    ( unshare -m sh "$0" inner >> "$GUEST_DIR/guest.log" 2>&1 < /dev/null ; echo "launcher: ended ($?)" >> "$GUEST_DIR/guest.log" ) &
    echo $! > "$GUEST_DIR/guest.pid"
    say "started (pid $(cat "$GUEST_DIR/guest.pid")); log: $GUEST_DIR/guest.log"
    ;;

inner)
    # Inside the guest's mount namespace.
    mount --make-rprivate / 2>/dev/null || mount -o rprivate / / 2>/dev/null || { echo "cannot make the mounts private: refusing to go on"; exit 1; }
    mnt=$GUEST_DIR/root
    mkdir -p "$mnt" "$GUEST_DIR/data"
    mount -o ro,loop "$GUEST_DIR/system.img" "$mnt" || { echo "cannot mount system.img"; exit 1; }
    mkdir -p "$mnt/product" "$mnt/vendor" "$mnt/data" 2>/dev/null
    mount -o ro,loop "$GUEST_DIR/product.img" "$mnt/product" || { echo "cannot mount product.img"; exit 1; }
    mount -o ro,loop "$GUEST_DIR/vendor.img" "$mnt/vendor" || { echo "cannot mount vendor.img"; exit 1; }
    # An init without the guest mode would run astraOS's whole boot on the HOST: kernel parameters,
    # fstab mounts, modules, hostname, watchdog, reboot. Found out the hard way on a test run. It is
    # looked for in the init itself before anything else is mounted or run.
    if ! grep -q ASTRA_GUEST "$mnt/system/bin/init" 2>/dev/null; then
        echo "REFUSING TO START: this system image's init has no guest mode (astra before f20b96e). Use a build from after it."
        exit 1
    fi
    mount --bind "$GUEST_DIR/data" "$mnt/data" || { echo "cannot bind the data folder"; exit 1; }
    # A /dev of its own.
    mount -t tmpfs -o mode=0755,nosuid tmpfs "$mnt/dev" || { echo "cannot mount /dev"; exit 1; }
    for n in $DEV_NODES; do
        [ -c "/dev/$n" ] || continue
        maj=$(stat -c %t "/dev/$n"); min=$(stat -c %T "/dev/$n")
        mknod -m 0666 "$mnt/dev/$n" c $((0x$maj)) $((0x$min)) 2>/dev/null || echo "no node /dev/$n"
    done
    mount -t proc -o nosuid,nodev,noexec proc "$mnt/proc" || { echo "cannot mount /proc"; exit 1; }
    mount -t sysfs -o ro,nosuid,nodev,noexec sysfs "$mnt/sys" 2>/dev/null
    echo "guest: mounted; starting init"
    ASTRA_GUEST=1 chroot "$mnt" /system/bin/init second_stage
    code=$?
    echo "guest: init ended with $code"
    exit "$code"
    ;;

stop)
    [ "$(id -u)" = 0 ] || die "run as root"
    running || { say "not running"; exit 0; }
    pid=$(cat "$GUEST_DIR/guest.pid")
    # init is the launcher's grandchild: ask it, by the root of its process.
    for p in /proc/[0-9]*; do
        p=${p#/proc/}
        [ "$(readlink "/proc/$p/root" 2>/dev/null)" = "$GUEST_DIR/root" ] || continue
        case "$(cat "/proc/$p/cmdline" 2>/dev/null | tr '\0' ' ')" in
        "/system/bin/init second_stage"*) kill -TERM "$p" ;;
        esac
    done
    i=0
    while running && [ $i -lt 30 ]; do sleep 1; i=$((i + 1)); done
    running && die "the guest did not end in 30 s (pid $pid): see $GUEST_DIR/guest.log"
    after=$(host_mounts)
    if [ "$after" = "$(cat "$GUEST_DIR/host-mounts.before" 2>/dev/null)" ]; then
        say "stopped; the host's mounts are as they were"
    else
        say "stopped, BUT the host's mounts differ from before: mount > $GUEST_DIR/mounts.after, compare with a fresh boot"
        cat /proc/self/mountinfo > "$GUEST_DIR/mounts.after"
    fi
    ;;

status)
    if running; then say "running (pid $(cat "$GUEST_DIR/guest.pid"))"; else say "not running"; fi
    tail -5 "$GUEST_DIR/guest.log" 2>/dev/null
    ;;

shell)
    running || die "not running"
    for p in /proc/[0-9]*; do
        p=${p#/proc/}
        [ "$(readlink "/proc/$p/root" 2>/dev/null)" = "$GUEST_DIR/root" ] || continue
        exec nsenter -t "$p" -m -r /system/bin/sh
    done
    die "no process of the guest found"
    ;;

*)
    echo "usage: $0 start|stop|status|shell" >&2
    exit 2
    ;;
esac
