#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build_iso.sh – remaster Debian-12 netinst into a fully unattended ISO
#
# Flags
#   -v | --vendor  NAME   (optional)  use **only** drives whose model matches NAME
#   -p | --password PASS  (optional)  local password for john (hashed SHA-512)
#   -i | --source  ISO    (optional)  path to netinst ISO (else auto-download)
#   -n | --dry-run         (optional)  dry run mode
#
# Example
#   ./build_iso.sh -v Seagate -p 'S0mething!'
#   ./build_iso.sh                        # use every disk, john key-only
# ---------------------------------------------------------------------------
set -euo pipefail

# ------------ defaults ------------------------------------------------------
ISO_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
ISO_SRC=""          # set with -i else download
VENDOR=""           # vendor filter (empty → all disks)
USERPW=""           # john's clear-text password (optional)
DRY_RUN=0            # dry run mode
ISO_OUT="debian-12.10.0-auto.iso"
# ------------ helpers -------------------------------------------------------
need() { command -v "$1" &>/dev/null || { echo "Missing $1"; exit 1; }; }
die()  { echo "Error: $*" >&2; exit 1; }
usage(){ echo "Usage: $0 [-v vendor] [-p password] [-i netinst.iso] [-n]"; exit 1; }

# ------------ parse CLI -----------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--vendor)
      if [[ -z "${2:-}" ]]; then usage; fi
      VENDOR="$2"; shift 2 ;;
    -p|--password)
      if [[ -z "${2:-}" ]]; then usage; fi
      USERPW="$2"; shift 2 ;;
    -i|--source)
      if [[ -z "${2:-}" ]]; then usage; fi
      ISO_SRC="$2"; shift 2 ;;
    -n|--dry-run)
      DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done

# ------------ tools ---------------------------------------------------------
for b in xorriso bsdtar wget openssl md5sum sed awk; do
  if ! command -v "$b" &>/dev/null; then
    echo "Missing $b"; exit 1;
  fi
  # In dry run, just note the check
  if [[ $DRY_RUN -eq 1 ]]; then echo "[DRY RUN] Would check for $b"; fi
done

# ------------ get netinst ---------------------------------------------------
if [[ -n $ISO_SRC ]]; then
  if [[ ! -f $ISO_SRC ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "[DRY RUN] Would check for --source file $ISO_SRC";
    else
      die "--source file not found"
    fi
  fi
else
  ISO_SRC="debian-12.10.0-amd64-netinst.iso"
  if [[ ! -f $ISO_SRC ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "[DRY RUN] Would download netinst ISO from $ISO_URL to $ISO_SRC";
    else
      echo "[+] Downloading netinst…"; wget -q --show-progress -O "$ISO_SRC" "$ISO_URL";
    fi
  fi
fi

# ------------ workspace -----------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
  WK="/tmp/dryrun-workspace"
  echo "[DRY RUN] Would create and use workspace $WK"
else
  WK=$(mktemp -d)
  trap 'echo "Temp dir: $WK"' EXIT
  bsdtar -C "$WK" -xf "$ISO_SRC"
  chmod -R u+w "$WK"
fi

# Write early.sh script to workspace
cat > "$WK/early.sh" <<'EOS'
#!/bin/sh
# EARLY_COMMAND logic for RAID10+LVM autodetect
set -e
exec 2>>/tmp/early_command_debug.log

echo "DEBUG: early_command started" >> /tmp/early_command_debug.log
VENDOR="$VENDOR"
echo "DEBUG: VENDOR variable (from VENDOR_ASSIGNMENT) in early_command is: '$VENDOR'" >> /tmp/early_command_debug.log
DISKS="$(for d in /sys/block/sd* /sys/block/vd* /sys/block/nvme*n1 ; do [ -e "$d" ] || continue; DEV="/dev/${d##*/}"; if [ -e "$d/removable" ] && grep -qx 1 "$d/removable"; then echo "DEBUG: Skipping removable disk $DEV" >> /tmp/early_command_debug.log; continue; fi; if [ -e "$d/device/model" ] && grep -qiE "(usb|flash|cdrom|dvd)" "$d/device/model"; then echo "DEBUG: Skipping usb/flash/cdrom/dvd $DEV" >> /tmp/early_command_debug.log; continue; fi; mod="$(cat "$d/device/model" 2>/dev/null || echo "")"; if [ -n "$VENDOR" ]; then if echo "$mod" | grep -Fqi "$VENDOR"; then echo "DEBUG: Disk $DEV model '$mod' matches VENDOR '$VENDOR'" >> /tmp/early_command_debug.log; else echo "DEBUG: Disk $DEV model '$mod' does NOT match VENDOR '$VENDOR', skipping" >> /tmp/early_command_debug.log; continue; fi; fi; echo "DEBUG: Found eligible disk $DEV model '$mod'" >> /tmp/early_command_debug.log; printf "%s " "$DEV"; done; )"
echo "DEBUG: DISKS='$DISKS'" >> /tmp/early_command_debug.log
ND=$(echo $DISKS | wc -w)
echo "DEBUG: ND=$ND" >> /tmp/early_command_debug.log
if (( ND < 2 )) || (( (ND % 2) != 0 )); then echo "DEBUG: Error: Need even number of disks (>=2) for RAID10, found $ND. Disks: '$DISKS'" >> /tmp/early_command_debug.log; logger -t preseed "Need even number of disks (>=2) for RAID10, found $ND. Disks: '$DISKS'"; exit 1; fi
echo "DEBUG: Disk check passed. Setting partman-auto/method raid" >> /tmp/early_command_debug.log
debconf-set partman-auto/method raid
echo "DEBUG: Setting partman-auto/disk='$DISKS'" >> /tmp/early_command_debug.log
debconf-set partman-auto/disk "$DISKS"
echo "DEBUG: Setting partman-auto/expert_recipe" >> /tmp/early_command_debug.log
debconf-set partman-auto/expert_recipe "raid10-lvm :: \\ 1024 1024 1024 ext4 \$primary{ } \$bootable{ } method{ raid } . \\ 1000 1000 -1 lvm method{ raid } ."
echo "DEBUG: expert_recipe set. Proceeding to BOOT/PV construction." >> /tmp/early_command_debug.log
BOOT=""
PV=""
echo "DEBUG: Initialized BOOT and PV. Starting loop..." >> /tmp/early_command_debug.log
for d in $DISKS; do echo "DEBUG: Loop for disk '$d'" >> /tmp/early_command_debug.log; [ "${d#nvme}" != "$d" ] && SFX=p || SFX=""; BOOT="${BOOT}${d}${SFX}1#"; PV="${PV}${d}${SFX}2#"; echo "DEBUG: d='$d', SFX='$SFX', BOOT='$BOOT', PV='$PV'" >> /tmp/early_command_debug.log; done
echo "DEBUG: Loop finished. BOOT='$BOOT', PV='$PV'" >> /tmp/early_command_debug.log
BOOT=${BOOT%#}
PV=${PV%#}
echo "DEBUG: Trimmed BOOT='$BOOT', PV='$PV'" >> /tmp/early_command_debug.log
debconf-set partman-auto-raid/recipe "1 $ND 0 ext4 /boot $BOOT . 10 $ND 0 lvm - $PV ."
echo "DEBUG: partman-auto-raid/recipe set." >> /tmp/early_command_debug.log
debconf-set partman-md/confirm true
debconf-set partman-md/confirm_nooverwrite true
debconf-set partman/confirm_write_new_label true
echo "DEBUG: Final md and partman confirmations set. early_command finished." >> /tmp/early_command_debug.log
EOS
chmod +x "$WK/early.sh"

# Set early_command in preseed to run the script from /cdrom
PRESEED="$WK/preseed.cfg"
awk '
  {
    if ($0 ~ /{{EARLY_COMMAND_HERE}}/) {
      print "d-i partman/early_command string /cdrom/early.sh"
    } else {
      print $0
    }
  }
' preseed.template.cfg > "$PRESEED"

if [[ -n $USERPW ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY RUN] Would hash password and add to $PRESEED."
  else
    HASH=$(openssl passwd -6 "$USERPW")
    sed -i '/passwd\/user-password-crypted/d' "$PRESEED"
    echo "d-i passwd/user-password-crypted password $HASH" >> "$PRESEED"
  fi
fi

# ------------ patch boot loaders -------------------------------------------
ISO_TXT="$WK/isolinux/txt.cfg"
ISO_CFG="$WK/isolinux/isolinux.cfg"
GRUB_CFG="$WK/boot/grub/grub.cfg"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY RUN] Would patch $ISO_TXT, $ISO_CFG, $GRUB_CFG for automated install."
else
  awk '
   BEGIN{done=0}
   /^label install/ && !done{
     print "label auto";
     print "  menu label ^Automated install";
     print "  kernel /install.amd/vmlinuz";
     print "  append vga=788 console=ttyS0,115200n8 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet";
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
      -e '0,/^[[:space:]]*linux /  s?linux .*?linux /install.amd/vmlinuz console=ttyS0,115200n8 auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet?' \
      "$GRUB_CFG"
fi

# ------------ preseed checker -----------------------------------------------
check_preseed() {
  local file="$1"
  # Check that early_command is a single line (not split across lines)
  local ec_lines
  ec_lines=$(grep -n '^d-i partman/early_command string' "$file" | cut -d: -f1)
  if [[ -n "$ec_lines" ]]; then
    for n in $ec_lines; do
      # Check if the next line is also not a preseed directive (i.e., the early_command is split)
      next_line=$(awk "NR==$((n+1)){print}" "$file")
      if [[ -n "$next_line" && ! "$next_line" =~ ^d-i ]]; then
        echo "[ERROR] early_command is split across lines!" >&2
        echo "[DEBUG] early_command line: $(awk "NR==$n{print}" "$file")" >&2
        echo "[DEBUG] next line: $next_line" >&2
        return 1
      fi
    done
  fi
  # Check preseed syntax with debconf-set-selections if available
  if command -v debconf-set-selections >/dev/null 2>&1; then
    # Filter out lines that debconf-set-selections can't parse
    grep -v '^d-i passwd/user-password-crypted ' "$file" > "$file.debconf"
    if ! debconf-set-selections -c "$file.debconf" >/dev/null 2>&1; then
      echo "[ERROR] debconf-set-selections reports a syntax error in $file (filtered)!" >&2
      debconf-set-selections -c "$file.debconf"  # Show the error
      rm -f "$file.debconf"
      return 1
    fi
    rm -f "$file.debconf"
  else
    echo "[WARNING] debconf-set-selections not found; skipping syntax check." >&2
  fi
  return 0
}
if [[ $DRY_RUN -eq 0 ]]; then
  if ! check_preseed "$PRESEED"; then
    echo "[FATAL] Preseed validation failed. Aborting build." >&2
    exit 1
  fi
fi

# ------------ md5sums & ISO -------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY RUN] Would generate md5sum.txt in $WK."
  echo "[DRY RUN] Would create ISO $ISO_OUT with xorriso."
else
  ( cd "$WK" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt )
  ISO_OUT="debian-12.10.0-auto.iso"
  rm -f "$ISO_OUT"
  xorriso -as mkisofs -r -iso-level 3 -l \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$ISO_OUT" "$WK"
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[DRY RUN] ✅  Finished (dry run, no ISO created)"
else
  echo "✅  Finished $ISO_OUT"
fi
