#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build_iso.sh  –  remaster Debian-12 netinst into a fully unattended ISO
#
# Flags:
#   -m | --mode      prod | test      (required)
#   -p | --password  "ClearText"      (optional – hashes to SHA-512)
#   -i | --source    netinst.iso      (optional – skip auto-download)
#
# Example:
#   ./build_iso.sh -m prod -p 'Str0ng!'          # Seagate filter + local pwd
#   ./build_iso.sh -m test                       # VM/CI ISO, key-only
# ---------------------------------------------------------------------------
set -euo pipefail

# ---------------- defaults --------------------------------------------------
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
ISO_SRC=""           # set via -i else auto-download
MODE=""              # prod | test
USERPW=""            # when set → hashed and inserted

# ---------------- helpers ---------------------------------------------------
need() { command -v "$1" &>/dev/null || { echo "Missing $1"; exit 1; }; }
die()  { echo "Error: $*" >&2; exit 1; }
usage(){ echo "Usage: $0 -m prod|test [-p password] [-i netinst.iso]"; exit 1; }

# ---------------- arg parse --------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode)      MODE="$2"; shift 2 ;;
    -p|--password)  USERPW="$2"; shift 2 ;;
    -i|--source)    ISO_SRC="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$MODE" == "prod" || "$MODE" == "test" ]] || usage

PRESEED_SRC="preseed.${MODE}.cfg"
[[ -r "$PRESEED_SRC" ]] || die "$PRESEED_SRC not found"

ISO_OUT="debian-12.10.0-${MODE}.iso"

# ---------------- tool checks ------------------------------------------------
for b in xorriso bsdtar wget openssl md5sum sed awk; do need "$b"; done

# ---------------- acquire original ISO --------------------------------------
if [[ -n "$ISO_SRC" ]]; then
  [[ -f "$ISO_SRC" ]] || die "--source file not found"
else
  ISO_SRC="debian-12.10.0-amd64-netinst.iso"
  [[ -f "$ISO_SRC" ]] || { echo "[+] Downloading netinst…"; wget -q --show-progress -O "$ISO_SRC" "$ISO_URL"; }
fi

# ---------------- prepare workspace -----------------------------------------
WORKDIR=$(mktemp -d)
trap 'echo "Temp dir: $WORKDIR"' EXIT
bsdtar -C "$WORKDIR" -xf "$ISO_SRC"
chmod -R u+w "$WORKDIR"             # allow in-place edits

# ---------------- preseed ----------------------------------------------------
cp "$PRESEED_SRC" "$WORKDIR/preseed.cfg"
if [[ -n "$USERPW" ]]; then
  HASH=$(openssl passwd -6 "$USERPW")
  sed -i '/passwd\/user-password-crypted/d' "$WORKDIR/preseed.cfg"
  echo "d-i passwd/user-password-crypted password $HASH" >> "$WORKDIR/preseed.cfg"
  echo "[+] Embedded SHA-512 hash for john"
else
  echo "[+] john will be password-less (SSH-key only)"
fi

# ---------------- BIOS (ISOLINUX) -------------------------------------------
ISO_TXT="$WORKDIR/isolinux/txt.cfg"
ISO_CFG="$WORKDIR/isolinux/isolinux.cfg"

# 1. create a dedicated 'auto' label (before first 'label install')
awk '
  BEGIN {done=0}
  /^label install/ && !done {
      print "label auto";
      print "  menu label ^Automated install";
      print "  kernel /install.amd/vmlinuz";
      print "  append vga=788 console=ttyS0,115200n8 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet";
      done=1
  }
  {print}
' "$ISO_TXT" > "$ISO_TXT.new" && mv "$ISO_TXT.new" "$ISO_TXT"

# 2. boot that label instantly
sed -i 's/^default .*/default auto/' "$ISO_CFG"
sed -i 's/^timeout .*/timeout 0/'    "$ISO_CFG"

# ---------------- UEFI (GRUB) -----------------------------------------------
GRUB_CFG="$WORKDIR/boot/grub/grub.cfg"

# put automated entry first
sed -i '0,/^menuentry / s/menuentry .*/menuentry "Automated install" {/' "$GRUB_CFG"
sed -i '0,/^[[:space:]]*linux /  s?linux .*?linux /install.amd/vmlinuz console=ttyS0,115200n8 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' "$GRUB_CFG"
sed -i 's/^set timeout=.*/set timeout=0/' "$GRUB_CFG"
sed -i 's/^set default=.*/set default=0/' "$GRUB_CFG"

# ---------------- regenerate md5sums ----------------------------------------
( cd "$WORKDIR" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt )

# ----- ensure we can overwrite any old ISO ----------------------------
if [[ -e "$ISO_OUT" ]]; then rm -f "$ISO_OUT"; fi     # remove read-only copy

# ---------------- build final ISO -------------------------------------------

xorriso -as mkisofs -r -iso-level 3 -l \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c isolinux/boot.cat -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o "$ISO_OUT" "$WORKDIR"

echo "✅  Finished  $ISO_OUT"
