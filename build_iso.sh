#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build_iso.sh  – Remaster Debian-12 netinst ISO with fully-automated preseed
#
#   ./build_iso.sh  -m prod                   # production Seagate-filtered iso
#   ./build_iso.sh  -m test -p 'Str0ngP@ss!'  # test iso with john’s password
#
# Result:  debian-12.10.0-${mode}.iso
# ---------------------------------------------------------------------------
set -euo pipefail

# ---- defaults -------------------------------------------------------------
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
ISO_SRC="debian-12.10.0-amd64-netinst.iso"
MODE="prod"        # prod | test
USERPW=""          # empty → password-less john
# ---------------------------------------------------------------------------

usage() {
  echo "Usage: $0 -m <prod|test> [-p <password>]"
  exit 1
}

# ---- CLI flags ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode)      MODE="$2"; shift 2 ;;
    -p|--password)  USERPW="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ $MODE == "prod" || $MODE == "test" ]] || usage

# ---- pick preseed ---------------------------------------------------------
PRESEED_SRC="preseed.${MODE}.cfg"                   # must be in same dir
[[ -r $PRESEED_SRC ]] || { echo "Missing $PRESEED_SRC"; exit 1; }

ISO_OUT="debian-12.10.0-${MODE}.iso"

# ---- required tools -------------------------------------------------------
need() { command -v "$1" >/dev/null || { echo "Missing $1"; exit 1; }; }
for bin in xorriso bsdtar wget openssl md5sum sed; do need "$bin"; done

# ---- fetch original ISO if absent ----------------------------------------
if [[ ! -f $ISO_SRC ]]; then
  echo "[+] Downloading original ISO…"
  wget -q --show-progress "$ISO_URL" -O "$ISO_SRC"     # ISO download
fi

WORKDIR=$(mktemp -d)
trap 'echo "Temp dir: $WORKDIR"' EXIT

# ---- unpack ISO ----------------------------------------------------------
echo "[+] Extracting ISO to working tree…"
bsdtar -C "$WORKDIR" -xf "$ISO_SRC"                    # non-root extract

# ---- copy / patch preseed -------------------------------------------------
PRESEED="$WORKDIR/preseed.cfg"
cp "$PRESEED_SRC" "$PRESEED"

if [[ -n "$USERPW" ]]; then
  HASH=$(openssl passwd -6 "$USERPW")                  # $6$ SHA-512 hash
  sed -i '/user-password-crypted/d' "$PRESEED"
  echo "d-i passwd/user-password-crypted password $HASH" >> "$PRESEED"
  echo "[+] Embedded password hash for john (SHA-512)"
else
  echo "[+] john will be password-less (SSH-key-only)"
fi

# ---- patch boot menus for hands-free boot --------------------------------
sed -i '0,/^[ \t]*append / s?append .*?append vga=788 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' \
      "$WORKDIR/isolinux/txt.cfg"                      # isolinux menu
sed -i '0,/^[ \t]*linux / s?linux .*?linux /install.amd/vmlinuz auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' \
      "$WORKDIR/boot/grub/grub.cfg"                    # grub menu (UEFI)

# ---- regenerate md5sum.txt ------------------------------------------------
echo "[+] Re-creating md5sum.txt"
(cd "$WORKDIR" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt)   # checksum list 

# ---- build hybrid ISO -----------------------------------------------------
echo "[+] Building $ISO_OUT"
xorriso -as mkisofs -r -J -joliet-long -l \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \      # MBR image
  -c isolinux/boot.cat -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat \                              # make GPT hybrid
  -o "$ISO_OUT" "$WORKDIR"

echo "✅ ISO created → $ISO_OUT"
