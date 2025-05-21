# debian-raid10-autoiso

## Fully-Automated Debian 12 ISO (RAID-10 + LVM)

This repository provides a script to build a **fully unattended Debian 12 installer ISO** that automatically sets up RAID-10 (on 4 disks) and LVM (optional) on user-specified disks. The ISO is suitable for both bare-metal and virtualized environments.

---

### Features
- **Automated RAID-10 setup on 4 disks**: The installer uses a preseed file to configure RAID-10 for `/` and swap, and RAID1 for `/boot`.
- **No early_command or external scripts**: The preseed is simple, robust, and easy to maintain.
- **User-defined disks**: Specify which disks to use at build time, or use the default (`/dev/sda /dev/sdb /dev/sdc /dev/sdd`).
- **Optional password for user**: You can provide a password for the default user, or rely on SSH key authentication only.
- **Dry run mode**: Test the build process without making any changes or creating files.

---

### Prerequisites (Host)

| Package                              | Why                                                         | 
| ------------------------------------ | ----------------------------------------------------------- |
| `xorriso`                            | rebuild hybrid BIOS/UEFI ISO                                |
| `isolinux`                           | ships `isohdpfx.bin` MBR needed by `xorriso -isohybrid-mbr` |
| `grub-pc-bin` + `grub-efi-amd64-bin` | provide the EFI boot image                                  |
| `bsdtar` ( `libarchive-tools` )      | unpacks ISO without root                                    |
| `openssl`                            | creates SHA-512 hash with `openssl passwd -6`               |
| `wget`, `md5sum`, `sed`, `awk`       | misc helpers                                                |

Install them on Debian/Ubuntu:

```bash
sudo apt update
sudo apt install xorriso isolinux grub-pc-bin grub-efi-amd64-bin libarchive-tools openssl wget debconf-utils
```

---

### Usage

```bash
./build_iso.sh [-d "/dev/sda /dev/sdb /dev/sdc /dev/sdd"] [-p password] [-i netinst.iso] [-n]
```

| Flag (long / short) | Required | Example | Effect |
|---------------------|----------|---------|--------|
| `--disks`  `-d`     | yes      | `-d "/dev/sda /dev/sdb /dev/sdc /dev/sdd"` | Use these disks for RAID10. Default: `/dev/sda /dev/sdb /dev/sdc /dev/sdd` |
| `--password`  `-p`  | optional | `-p "M0nkeyLadd3r!"` | Hashes the clear-text with `openssl passwd -6` and injects it, so **john** gets an interactive password as well as his SSH key. Omit to keep john password-less. |
| `--source`  `-i`    | optional | `-i ~/isos/debian-12.10.0-amd64-netinst.iso` | Use a locally stored netinst ISO instead of downloading the current image from debian.org. |
|  `--ssh-key` `-k`   | yes      | `-k` | SSH public key file | 
| `--dry-run`  `-n`   | optional | `-n` | Run the build in dry run mode (no files are created or modified). |

If `--source` is **not** supplied the script checks for  
`debian-12.10.0-amd64-netinst.iso` in the working directory and downloads it automatically when missing.

#### **Examples:**

- **Default (use /dev/sda /dev/sdb /dev/sdc /dev/sdd for RAID10):**
  ```bash
  ./build_iso.sh
  ```
- **Custom disks (must be 4 for RAID10):**
  ```bash
  ./build_iso.sh -d "/dev/vda /dev/vdb /dev/vdc /dev/vdd"
  ```
- **Set a password for john:**
  ```bash
  ./build_iso.sh -p 'r00tMe!'
  ```
- **Use a local ISO:**
  ```bash
  ./build_iso.sh -i ~/Downloads/debian-12.10.0-amd64-netinst.iso
  ```
- **Dry run:**
  ```bash
  ./build_iso.sh -n
  ```

---

### How it works
- The script injects your disk list into the preseed at the `{{DISKS_HERE}}` placeholder.
- The preseed configures RAID-10 and partitioning using only standard preseed directives—no early_command or custom scripts.
- The build process does not run any disk detection or debconf-set on the build host.

---

### Customizing the Preseed

In your `preseed.template.cfg`, include this line where you want the disk list:

```
{{DISKS_HERE}}
```

The script will replace this with:
```
d-i partman-auto/disk string /dev/sda /dev/sdb /dev/sdc /dev/sdd
```
(or whatever disks you specify).

The preseed is set up for:
- `/boot`: 1GB, RAID1 (mirrored on all disks)
- `swap`: 4GB, RAID10 (across all disks)
- `/` (root): all remaining space, RAID10 (across all disks)

**To use a different number of disks or a different RAID/LVM layout, edit the preseed/template accordingly.**

---

### Quick KVM test

```bash
for i in {1..4}; do qemu-img create -f qcow2 disk$i.qcow2 10G; done
virt-install --name debian-auto --ram 4096 --vcpus 2 \
  --disk disk1.qcow2,bus=virtio --disk disk2.qcow2,bus=virtio \
  --disk disk3.qcow2,bus=virtio --disk disk4.qcow2,bus=virtio \
  --graphics none --console pty,target_type=serial \
  --cdrom debian-12.10.0-auto.iso --osinfo detect=on,require=off

virsh console debian-auto
```

---

### Troubleshooting
- If the installer reports: `The installer failed to process the preconfiguration file from file:///cdrom/preseed.cfg. The file may be corrupt.`
  - Check that your preseed is valid and that the disk list is correct.
  - You can manually inspect the generated `preseed.cfg` after build for further debugging.
- If the installer cannot find the disks, make sure the device names match those in your environment.
- For RAID10, you must specify exactly 4 disks in the disk list and in the RAID recipe.

---

### Clean up : Stop and delete VM

```bash
virsh shutdown debian-auto 
# OR if VM does not respond 
virsh destroy debian-auto
virsh undefine debian-auto --remove-all-storage
```

---

### Customising
- Edit the disk list at build time with `-d` or by editing the preseed template.
- Adjust RAID10 layout by editing the expert_recipe and partman-auto-raid/recipe in the preseed.
- Change GRUB menu timeout in `isolinux/txt.cfg` and `boot/grub/grub.cfg` before rebuilding.
- For other RAID/LVM layouts or disk counts, edit the preseed/template accordingly.

---

### Notes
- The ISO is generic and can be used on any compatible hardware or VM (with 4 disks for RAID10).
- The build script is robust and will abort if the preseed is malformed.
- For advanced customisation, edit `build_iso.sh` and `preseed.template.cfg` as needed.