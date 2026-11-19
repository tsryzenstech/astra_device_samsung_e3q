#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds vendor.img, the S24 Ultra's vendor partition of the guest: build.prop from board.conf
# and vendor/etc/init (needs mke2fs, from e2fsprogs).
#
#   scripts/make-vendor.sh OUTFILE
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: make-vendor.sh OUTFILE}
# shellcheck disable=SC1091
source "$here/board.conf"
tree=$(mktemp -d)
trap 'rm -rf "$tree"' EXIT
mkdir -p "$tree/etc/init"
cp "$here"/vendor/etc/init/*.rc "$tree/etc/init/"
sed -e "s|@DEVICE@|$DEVICE|" -e "s|@DEVICE_MODEL@|$DEVICE_MODEL|" -e "s|@DEVICE_BRAND@|$DEVICE_BRAND|" \
    -e "s|@DEVICE_MANUFACTURER@|$DEVICE_MANUFACTURER|" -e "s|@SOC@|$SOC|" -e "s|@UI_SCALE@|$UI_SCALE|" \
    -e "s|@BATTERY_CAPACITY_MAH@|$BATTERY_CAPACITY_MAH|" -e "s|@ANDROID_DENSITY@|$ANDROID_DENSITY|" \
    -e "s|@MOTION_BLUR@|$MOTION_BLUR|" -e "s|@DISPLAY_REFRESH@|$DISPLAY_REFRESH|" \
    -e "s|@OTA_REPOSITORY@|$OTA_REPOSITORY|" "$here/vendor/build.prop.in" > "$tree/build.prop"
rm -f "$out"
E2FSPROGS_FAKE_TIME=1700000000 mke2fs -q -t ext4 -b 4096 -L vendor -O ^has_journal -E root_owner=0:0 -d "$tree" "$out" 8M
echo "wrote $out"
