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
### 1. Prerequisites (Host)

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
### Build both variants

```bash
./build_iso.sh prod   # vendor-filtered ISO for real hardware
./build_iso.sh test   # generic ISO for VMs / dev boxes
```


