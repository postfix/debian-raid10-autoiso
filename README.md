# debian-raid10-autoiso
## Fully-Automated Debian 12 ISO (RAID-10 + LVM)

This repository contains:
```
debian-raid10-autoiso/
├── build_iso.sh
├── preseed.production.cfg   # <-- filter keeps only Seagate drives
└── preseed.test.cfg         # <-- accepts every /dev/sd*   (good for VMs)  
└── README.md    # <-- these instructions  
```
### Preseed
Both preseeds are identical except for one line (highlighted below).
- preseed.production.cfg – vendor-filtered
```bash
###  EARLY_COMMAND — keep ONLY disks whose model contains “Seagate”
d-i partman/early_command string \
  DISKS="$(for d in /sys/block/sd*; do \
      m=$(cat $d/device/model 2>/dev/null); \
      if echo "$m" | grep -qi Seagate; then echo -n "/dev/${d##*/} "; fi; done)"; \
  # (the remainder is unchanged …)
```
- preseed.test.cfg – accept any vendor disk
```bash
###  EARLY_COMMAND — accept every /sys/block/sd*  (no model filter)
d-i partman/early_command string \
  DISKS="$(for d in /sys/block/sd*; do echo -n "/dev/${d##*/} "; done)"; \
  # (the remainder is identical …)
```

### Prerequisites (Host)

| Package                              | Why                                                         | 
| ------------------------------------ | ----------------------------------------------------------- |
| `xorriso`                            | rebuild hybrid BIOS/UEFI ISO                                |
| `isolinux`                           | ships `isohdpfx.bin` MBR needed by `xorriso -isohybrid-mbr` |
| `grub-pc-bin` + `grub-efi-amd64-bin` | provide the EFI boot image                                  |
| `bsdtar` ( `libarchive-tools` )      | unpacks ISO without root                                    |
| `openssl`                            | creates SHA-512 hash with `openssl passwd -6`               |
| `wget`, `md5sum`, `sed`              | misc helpers                                                | 



* Install them on Debian/Ubuntu: *

```bash
sudo apt update
sudo apt install xorriso isolinux grub-pc-bin grub-efi-amd64-bin libarchive-tools openssl wget
```
### Build

```bash
./build_iso.sh -m prod   # vendor-filtered ISO for real hardware
./build_iso.sh -m test -p "r00t  # generic ISO for VMs / dev boxes
```
## Command-line flags recap

| Flag (long / short) | Required | Example | Effect |
|---------------------|----------|---------|--------|
| `--mode`  `-m`      | **yes**  | `-m prod` or `-m test` | Chooses which preseed file to embed:<br>• **prod** → `preseed.production.cfg` (Seagate-filter)<br>• **test** → `preseed.test.cfg` (no vendor filter) |
| `--password`  `-p`  | optional | `-p "M0nkeyLadd3r!"` | Hashes the clear-text with `openssl passwd -6` and injects it, so **john** gets an interactive password as well as his SSH key. Omit to keep john password-less. |
| `--source`  `-i`    | optional | `-i ~/isos/debian-12.10.0-amd64-netinst.iso` | Use a locally stored netinst ISO instead of downloading the current image from debian.org. |

If `--source` is **not** supplied the script checks for  
`debian-12.10.0-amd64-netinst.iso` in the working directory and downloads it automatically when missing. :contentReference[oaicite:0]{index=0}



### Customising

- Change vendor filter – edit the grep -i Seagate line in partman/early_command.
- Swap size – leave “guided_size max” (installer creates 4 GiB LV) or add an explicit LVM recipe if you need a fixed split.
- GRUB menu timeout – adjust in isolinux/txt.cfg and boot/grub/grub.cfg before rebuilding.

### Quick test in KVM (four virtual drives, headless)

```bash
for i in {1..4}; do qemu-img create -f qcow2 disk$i.qcow2 10G; done
virt-install --name debian-auto --ram 4096 --vcpus 2 \
  --disk disk1.qcow2,bus=virtio --disk disk2.qcow2,bus=virtio \
  --disk disk3.qcow2,bus=virtio --disk disk4.qcow2,bus=virtio \
  --graphics none --console pty,target_type=serial \
  --cdrom debian-12.10.0-auto.iso \
  --extra-args 'console=ttyS0,115200n8'
virsh console debian-auto          # watch the unattended install
```
### First login
```bash
ssh john@<new-ip>   # logs in via your SSH key
sudo lvs            # shows vg0/root + vg0/swap
cat /proc/mdstat    # shows md0 (RAID1) + md1 (RAID10)
```
