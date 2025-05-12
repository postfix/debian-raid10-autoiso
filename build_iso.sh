#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  build_iso.sh  –  Remaster Debian-12 netinst ISO with unattended preseed
#
#  Flags:
#    -m | --mode      prod | test          (required)
#    -p | --password  "ClearTextPass"      (optional – hashed to SHA-512)
#    -i | --source    /path/to/netinst.iso (optional – skip auto-download)
#
#  Examples:
#    ./build_iso.sh -m prod
#    ./build_iso.sh -m test -p 'S0m3P@ss!'
#    ./build_iso.sh -m prod -i ~/Downloads/debian-12.10.0-amd64-netinst.iso
# ---------------------------------------------------------------------------
set -euo pipefail

# ---- defaults -------------------------------------------------------------
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
ISO_SRC=""               # will hold path after flag parse
MODE=""
USERPW=""

# ---- helper ---------------------------------------------------------------
need() { command -v "$1" &>/dev/null || { echo "Missing $1"; exit 1; }; }
usage(){ echo "Usage: $0 -m prod|test [-p password] [-i path_to_iso]"; exit 1; }

# ---- parse CLI flags (getopts long+short) ---------------------------------
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
[[ -r "$PRESEED_SRC" ]] || { echo "File $PRESEED_SRC not found"; exit 1; }

ISO_OUT="debian-12.10.0-${MODE}.iso"

# ---- tooling checks -------------------------------------------------------
for bin in xorriso bsdtar wget openssl md5sum sed; do need "$bin"; done  # getopts refs: SO & GfG :contentReference[oaicite:0]{index=0}

# ---- acquire netinst ISO --------------------------------------------------
if [[ -n "$ISO_SRC" ]]; then
  [[ -f "$ISO_SRC" ]] || { echo "Provided --source not found"; exit 1; }
else
  ISO_SRC="debian-12.10.0-amd64-netinst.iso"
  [[ -f "$ISO_SRC" ]] || { echo "[+] Downloading netinst…"; wget -q --show-progress -O "$ISO_SRC" "$ISO_URL"; }  :contentReference[oaicite:1]{index=1}
fi

# ---- unpack original ISO --------------------------------------------------
WORKDIR=$(mktemp -d)
bsdtar -C "$WORKDIR" -xf "$ISO_SRC"      # Debian wiki recommends bsdtar :contentReference[oaicite:2]{index=2}

# ---- copy & patch preseed --------------------------------------------------
PRESEED="$WORKDIR/preseed.cfg"
cp "$PRESEED_SRC" "$PRESEED"

if [[ -n "$USERPW" ]]; then                       # hash w/ OpenSSL SHA-512 :contentReference[oaicite:3]{index=3}
  HASH=$(openssl passwd -6 "$USERPW")
  sed -i '/user-password-crypted/d' "$PRESEED"
  echo "d-i passwd/user-password-crypted password $HASH" >> "$PRESEED"
  echo "[+] Embedded SHA-512 hash for john"
else
  echo "[+] john remains password-less (SSH key only)"
fi

# ---- patch boot menus (BIOS & UEFI) ---------------------------------------
sed -i '0,/^[[:space:]]*append /s?append .*?append vga=788 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' \
      "$WORKDIR/isolinux/txt.cfg"                                       :contentReference[oaicite:4]{index=4}
sed -i '0,/^[[:space:]]*linux /s?linux .*?linux /install.amd/vmlinuz auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' \
      "$WORKDIR/boot/grub/grub.cfg"

# ---- regenerate md5sum list ----------------------------------------------
(cd "$WORKDIR" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt)   :contentReference[oaicite:5]{index=5}

# ---- rebuild hybrid ISO ---------------------------------------------------
xorriso -as mkisofs -r -J -joliet-long -l \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \        # isolinux MBR path :contentReference[oaicite:6]{index=6}
  -c isolinux/boot.cat -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat \                                # GPT hybrid flag :contentReference[oaicite:7]{index=7}
  -o "$ISO_OUT" "$WORKDIR"

echo "✅  Finished:  $ISO_OUT"
echo "    Working dir kept: $WORKDIR"
