#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Takes the guest's system and product images out of an astraOS release.

The guest runs astraOS's own userland, which every device build carries in its
`super` image (an Android "dynamic partitions" image, sparse): the system and
product partitions are the same for every phone, the vendor one is the phone's
(this repository builds its own: scripts/make-vendor.sh). So the guest is not
built again: it is taken from a release of astra_device_xiaomi_sweet, whose
userland is aarch64 musl, as the S24 Ultra's.

  extract-guest.py super.img[.gz] OUTDIR            writes OUTDIR/system.img and product.img
  extract-guest.py --list super.img[.gz]            lists the partitions

Reads the sparse format (raw, fill, don't care and CRC chunks), then the logical
partition metadata ("0PLA" at 12288), and copies each partition's extents.
"""
import gzip
import os
import struct
import sys

SPARSE_MAGIC = 0xED26FF3A
LP_MAGIC = 0x414C5030
SECTOR = 512
KEEP = ("system", "product")


def open_image(path):
    return gzip.open(path, "rb") if path.endswith(".gz") else open(path, "rb")


def unsparse(src, dst_path):
    """Writes the raw image of a sparse one; returns its size. A file that is not sparse is copied."""
    head = src.read(28)
    if len(head) < 28 or struct.unpack("<I", head[:4])[0] != SPARSE_MAGIC:
        src.seek(0)
        with open(dst_path, "wb") as out:
            while True:
                b = src.read(1 << 20)
                if not b:
                    break
                out.write(b)
        return os.path.getsize(dst_path)
    _, major, minor, file_hdr, chunk_hdr, blk_sz, total_blks, total_chunks, _ = struct.unpack("<IHHHHIIII", head)
    if major != 1:
        raise SystemExit("unsupported sparse format %d.%d" % (major, minor))
    src.read(file_hdr - 28)
    with open(dst_path, "wb") as out:
        for _ in range(total_chunks):
            ch = src.read(chunk_hdr)
            ctype, _, chunk_blocks, total_sz = struct.unpack("<HHII", ch[:12])
            size = chunk_blocks * blk_sz
            if ctype == 0xCAC1:         # raw
                left = size
                while left:
                    b = src.read(min(left, 1 << 20))
                    if not b:
                        raise SystemExit("the sparse image is cut short")
                    out.write(b)
                    left -= len(b)
            elif ctype == 0xCAC2:       # fill
                fill = src.read(4)
                block = fill * (blk_sz // 4)
                for _ in range(chunk_blocks):
                    out.write(block)
            elif ctype == 0xCAC3:       # don't care
                out.seek(size, 1)
            elif ctype == 0xCAC4:       # crc
                src.read(4)
            else:
                raise SystemExit("unknown sparse chunk %#x" % ctype)
        out.truncate(total_blks * blk_sz)
    return total_blks * blk_sz


def partitions(raw):
    """[(name, [(first_sector, num_sectors)])] from the logical partition metadata."""
    with open(raw, "rb") as f:
        f.seek(4096)
        geo = f.read(52)
        if struct.unpack("<I", geo[:4])[0] != 0x616C4467:      # "gDla"
            raise SystemExit("no logical partition geometry: this is not a super image")
        meta_max = struct.unpack("<I", geo[40:44])[0]
        f.seek(4096 * 3)                                          # primary metadata copy
        h = f.read(128)
        magic, major, minor, hdr_size = struct.unpack("<IHHI", h[:12])
        if magic != LP_MAGIC:
            raise SystemExit("no logical partition metadata")
        tables_size = struct.unpack("<I", h[44:48])[0]
        # partitions, extents, groups, block devices descriptors: offset, count, entry size
        pt = struct.unpack("<III", h[80:92])
        ex = struct.unpack("<III", h[92:104])
        f.seek(4096 * 3 + hdr_size)
        tables = f.read(tables_size)
    parts = []
    for i in range(pt[1]):
        e = tables[pt[0] + i * pt[2]: pt[0] + (i + 1) * pt[2]]
        name = e[:36].split(b"\0")[0].decode()
        first, num = struct.unpack("<II", e[40:48])
        extents = []
        for j in range(first, first + num):
            x = tables[ex[0] + j * ex[2]: ex[0] + (j + 1) * ex[2]]
            sectors, ttype, data = struct.unpack("<QIQ", x[:20])
            if ttype != 0:
                raise SystemExit("%s: only linear extents are supported" % name)
            extents.append((data, sectors))
        parts.append((name, extents))
    return parts


def main():
    args = sys.argv[1:]
    listing = bool(args) and args[0] == "--list"
    if listing:
        args = args[1:]
    if not args or (not listing and len(args) != 2):
        sys.exit(__doc__)
    work = (args[1] if not listing else "/tmp") + "/.super.raw"
    os.makedirs(os.path.dirname(work), exist_ok=True)
    with open_image(args[0]) as src:
        unsparse(src, work)
    try:
        parts = partitions(work)
        for name, extents in parts:
            print("%-10s %7.1f MiB" % (name, sum(s for _, s in extents) * SECTOR / 1048576))
        if listing:
            return
        with open(work, "rb") as raw:
            for name, extents in parts:
                if name not in KEEP:
                    continue
                out_path = os.path.join(args[1], name + ".img")
                with open(out_path, "wb") as out:
                    for first, sectors in extents:
                        raw.seek(first * SECTOR)
                        left = sectors * SECTOR
                        while left:
                            b = raw.read(min(left, 1 << 20))
                            out.write(b)
                            left -= len(b)
                print("wrote", out_path)
    finally:
        os.unlink(work)


if __name__ == "__main__":
    main()
