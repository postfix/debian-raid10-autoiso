# debian-raid10-autoiso
## Fully-Automated Debian 12 ISO (RAID-10 + LVM)

This repository contains:
```
my-auto-debian/
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

| package | why |
|---------|-----|
| `xorriso` | repack hybrid ISO |
| `bsdtar`  | non-root extraction |
| `isolinux`| provides `isohdpfx.bin` MBR |
| `wget`    | download original ISO |
| `grub-pc-bin` or `grub-efi-amd64-bin` | supplies `grub-mkstandalone` (for UEFI) |

Install them on Debian/Ubuntu:

```bash
sudo apt update
sudo apt install xorriso isolinux genisoimage grub-pc-bin grub-efi-amd64-bin bsdtar wget
```
### Build

```bash
./build_iso.sh prod   # vendor-filtered ISO for real hardware
./build_iso.sh test   # generic ISO for VMs / dev boxes
```
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
