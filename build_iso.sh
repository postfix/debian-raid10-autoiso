#!/usr/bin/env bash
#  build_iso.sh  ── remaster Debian-12 netinst ISO with embedded preseed
#  usage:  ./build_iso.sh </path/to/debian-12.10.0-amd64-netinst.iso>
#          (if no argument is given the script downloads the ISO)

set -euo pipefail
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
ISO_IN="${1:-debian-12.10.0-amd64-netinst.iso}"
ISO_OUT="debian-12.10.0-auto.iso"
WORKDIR="$(mktemp -d)"
PRESEED="preseed.cfg"          # same directory as this script

# ── prerequisites ───────────────────────────────────────────────
need() { command -v "$1" >/dev/null || { echo "Missing $1"; exit 1; }; }
for bin in xorriso bsdtar grub-mkstandalone md5sum; do need "$bin"; done

# ── obtain original ISO ─────────────────────────────────────────
if [[ ! -e "$ISO_IN" ]]; then
  echo "Downloading $ISO_URL…"
  wget -q --show-progress -O "$ISO_IN" "$ISO_URL"      # :contentReference[oaicite:1]{index=1}
fi

# ── unpack to working tree ──────────────────────────────────────
echo "Extracting ISO…"
bsdtar -C "$WORKDIR" -xf "$ISO_IN"                     # :contentReference[oaicite:2]{index=2}

# ── copy your preseed into root of ISO ─────────────────────────
cp "$PRESEED" "$WORKDIR/preseed.cfg"

# ── patch BIOS isolinux/txt.cfg  (first label) ─────────────────
ISOLINUX_CFG="$WORKDIR/isolinux/txt.cfg"
sed -i '0,/^  append / s?^  append .*?  append vga=788 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' "$ISOLINUX_CFG"   # :contentReference[oaicite:3]{index=3}

# ── patch UEFI grub.cfg  (first menuentry) ─────────────────────
GRUB_CFG="$WORKDIR/boot/grub/grub.cfg"
sed -i '0,/linux/ s?linux .*?linux /install.amd/vmlinuz auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' "$GRUB_CFG"

# ── update checksums (Debian requires md5sum.txt) ──────────────
echo "Updating md5sum.txt…"
(
  cd "$WORKDIR"
  find . -type f -print0 | xargs -0 md5sum > md5sum.txt   # :contentReference[oaicite:4]{index=4}
)

# ── rebuild hybrid ISO ─────────────────────────────────────────
echo "Rebuilding ISO to $ISO_OUT…"
xorriso -as mkisofs -r -J -joliet-long -l \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \          # :contentReference[oaicite:5]{index=5}
  -c isolinux/boot.cat -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o "$ISO_OUT" "$WORKDIR"

echo "Done.  New ISO: $ISO_OUT"
echo "Temporary workdir preserved at: $WORKDIR"
