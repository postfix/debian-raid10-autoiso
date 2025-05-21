#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build_iso.sh – remaster Debian-12 netinst into a fully unattended ISO
#
# Flags
#   -d | --disks  DISKS   (optional)  user-supplied disk list (default: '/dev/sda /dev/sdb /dev/sdc /dev/vdd')
#   -p | --password PASS  (optional)  local password for john (hashed SHA-512)
#   -i | --source  ISO    (optional)  path to netinst ISO (else auto-download)
#   -k | --ssh-key  KEY   (optional)  path to SSH public key
#   -n | --dry-run         (optional)  dry run mode
#
# Example
#   ./build_iso.sh -d /dev/sdb -p 'S0mething!'
#   ./build_iso.sh                        # use every disk, john key-only
# ---------------------------------------------------------------------------
set -euo pipefail

# ------------ defaults ------------------------------------------------------
DISKS="/dev/sda /dev/sdb /dev/sdc /dev/vdd"
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
ISO_SRC=""
USERPW=""
DRY_RUN=0
ISO_OUT="debian-12.10.0-auto.iso"
SSH_PUBKEY_CONTENT=""

# ------------ parse CLI -----------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--disks)
      if [[ -z "${2:-}" ]]; then echo "Missing argument for --disks"; exit 1; fi
      DISKS="$2"; shift 2 ;;
    -p|--password)
      if [[ -z "${2:-}" ]]; then echo "Missing argument for --password"; exit 1; fi
      USERPW="$2"; shift 2 ;;
    -i|--source)
      if [[ -z "${2:-}" ]]; then echo "Missing argument for --source"; exit 1; fi
      ISO_SRC="$2"; shift 2 ;;
    -k|--ssh-key)
      if [[ -z "${2:-}" ]]; then echo "Missing argument for --ssh-key"; exit 1; fi
      if [[ ! -f "$2" ]]; then echo "SSH public key file not found: $2"; exit 1; fi
      SSH_PUBKEY_CONTENT=$(cat "$2")
      shift 2 ;;
    -n|--dry-run)
      DRY_RUN=1; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ------------ tools ---------------------------------------------------------
for b in xorriso bsdtar wget openssl md5sum sed awk; do
  command -v "$b" &>/dev/null || { echo "Missing $b"; exit 1; }
done

# ------------ get netinst ---------------------------------------------------
if [[ -n $ISO_SRC ]]; then
  [[ -f $ISO_SRC ]] || { echo "--source file not found"; exit 1; }
else
  ISO_SRC="debian-12.10.0-amd64-netinst.iso"
  [[ -f $ISO_SRC ]] || wget -q --show-progress -O "$ISO_SRC" "$ISO_URL"
fi

# ------------ workspace -----------------------------------------------------
WK=$(mktemp -d)
trap 'echo "Cleaning up temp dir: $WK"; rm -rf "$WK"' EXIT
bsdtar -C "$WK" -xf "$ISO_SRC"
chmod -R u+w "$WK"

# Parse disks into an array
read -ra DISK_ARR <<< "$DISKS"
NUM_DISKS=${#DISK_ARR[@]}

# Dynamically generate RAID device lists for expert recipe
RAID_DEVICES_BOOT=""
RAID_DEVICES_SWAP=""
RAID_DEVICES_ROOT=""
for d in "${DISK_ARR[@]}"; do
  RAID_DEVICES_BOOT+="${d}1#"
  RAID_DEVICES_ROOT+="${d}2#"
done
# Remove trailing #
RAID_DEVICES_BOOT=${RAID_DEVICES_BOOT%#}
RAID_DEVICES_ROOT=${RAID_DEVICES_ROOT%#}

# Generate GRUB install devices (comma+space separated)
GRUB_INSTALL_DEVICES=$(echo "$DISKS" | sed 's/ /, /g')

echo "Debug: NUM_DISKS = '${NUM_DISKS}'" >&2
echo "Debug: RAID_DEVICES_BOOT = '${RAID_DEVICES_BOOT}'" >&2
echo "Debug: RAID_DEVICES_ROOT = '${RAID_DEVICES_ROOT}'" >&2
echo "Debug: DISKS variable for preseed = '${DISKS}'" >&2

# ------------ build preseed -------------------------------------------------
PRESEED="$WK/preseed.cfg"
awk -v disks="$DISKS" \
    -v raid_boot="$RAID_DEVICES_BOOT" \
    -v raid_root="$RAID_DEVICES_ROOT" \
    -v grub_install_devices="$GRUB_INSTALL_DEVICES" \
    -v ssh_pubkey="$SSH_PUBKEY_CONTENT" \
    '{
      gsub(/{{DISKS_HERE_NO_QUOTES}}/, disks)
      gsub(/{{RAID_DEVICES_BOOT}}/, raid_boot)
      gsub(/{{RAID_DEVICES_SWAP}}/, raid_swap)
      gsub(/{{RAID_DEVICES_ROOT}}/, raid_root)
      gsub(/{{GRUB_INSTALL_DEVICES}}/, grub_install_devices)
      gsub(/{{SSH_PUBKEY_HERE}}/, ssh_pubkey)
      print
    }
' preseed.template.cfg > "$PRESEED"

if [[ -n $USERPW ]]; then
  HASH=$(openssl passwd -6 "$USERPW")
  sed -i '/passwd\/user-password-crypted/d' "$PRESEED"
  echo "d-i passwd/user-password-crypted password $HASH" >> "$PRESEED"
fi

# ------------ patch boot loaders -------------------------------------------
ISO_TXT="$WK/isolinux/txt.cfg"
ISO_CFG="$WK/isolinux/isolinux.cfg"
GRUB_CFG="$WK/boot/grub/grub.cfg"
awk '
 BEGIN{done=0}
 /^label install/ && !done{
   print "label auto";
   print "  menu label ^Automated install";
   print "  kernel /install.amd/vmlinuz";
   print "  append vga=791 console=ttyS0,115200n8 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet";
   print "  initrd /install.amd/initrd.gz";
   done=1}
 {print}' "$ISO_TXT" >"$ISO_TXT.new" && mv "$ISO_TXT.new" "$ISO_TXT"
sed -i \
    -e 's/^default .*/default auto/' \
    -e 's/^timeout .*/timeout 0/' \
    -e '1iserial 0 115200' \
    -e '1iprompt 0' \
    "$ISO_CFG"
sed -i \
    -e 's/^set default=.*/set default=0/' \
    -e 's/^set timeout=.*/set timeout=0/' \
    -e '0,/^menuentry / s/menuentry .*/menuentry "Automated install" {/' \
    -e '0,/^[[:space:]]*linux /  s?linux .*?linux /install.amd/vmlinuz vga=791 console=ttyS0,115200n8 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' \
    "$GRUB_CFG"

# ------------ md5sums & ISO -------------------------------------------------
( cd "$WK" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt )

rm -f "$ISO_OUT"
xorriso -as mkisofs -r -iso-level 3 -l \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c isolinux/boot.cat -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o "$ISO_OUT" "$WK"

echo "✅  Finished $ISO_OUT"
