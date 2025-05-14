# debian-raid10-autoiso
## Fully-Automated Debian 12 ISO (RAID-10 + LVM)

This repository provides a script to build a **fully unattended Debian 12 installer ISO** that automatically sets up RAID-10 and LVM on all detected not removable disks . The ISO is suitable for both bare-metal and virtualized environments.

---

### Features
- **Automated disk detection and RAID-10 + LVM setup**: The installer runs a dynamic early_command (injected at build time) that detects all eligible disks and configures RAID-10 and LVM automatically on the target machine.
- **No disk detection at build time**: The ISO is generic and can be used on any compatible hardware.
- **Preseed validation**: The build script checks the generated preseed for syntax issues before building the ISO, reducing the risk of installer errors.
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
| `wget`, `md5sum`, `sed`              | misc helpers                                                |

Install them on Debian/Ubuntu:

```bash
sudo apt update
sudo apt install xorriso isolinux grub-pc-bin grub-efi-amd64-bin libarchive-tools openssl wget debconf-utils
```

---

### Usage

```bash
./build_iso.sh [-v vendor] [-p password] [-i netinst.iso] [-n]
```

| Flag (long / short) | Required | Example | Effect |
|---------------------|----------|---------|--------|
| `--vendor`  `-v`    | optional | `-v Seagate` | Only use disks whose model matches the vendor string (e.g., only Seagate drives). Omit to use all disks. |
| `--password`  `-p`  | optional | `-p "M0nkeyLadd3r!"` | Hashes the clear-text with `openssl passwd -6` and injects it, so **john** gets an interactive password as well as his SSH key. Omit to keep john password-less. |
| `--source`  `-i`    | optional | `-i ~/isos/debian-12.10.0-amd64-netinst.iso` | Use a locally stored netinst ISO instead of downloading the current image from debian.org. |
| `--dry-run`  `-n`   | optional | `-n` | Run the build in dry run mode (no files are created or modified). |

If `--source` is **not** supplied the script checks for  
`debian-12.10.0-amd64-netinst.iso` in the working directory and downloads it automatically when missing.

---

### How it works
- The script injects a **single-line, properly-escaped shell script** into the preseed's `early_command`. This script runs on the target machine during installation, detects all eligible disks, and configures RAID-10 and LVM using debconf-set.
- The build process **does not run any disk detection or debconf-set on the build host**.
- After generating the preseed, the script runs a **checker** to validate the preseed file for syntax issues (such as unescaped newlines in early_command). If validation fails, the build aborts with a clear error message.

---

### Troubleshooting
- If the installer reports: `The installer failed to process the preconfiguration file from file:///cdrom/preseed.cfg. The file may be corrupt.`
  - The build script now checks for common preseed errors, especially in the early_command.
  - If you edit the preseed or script, ensure the early_command is a single properly-escaped line (no unescaped newlines, all quotes escaped).
  - You can manually inspect the generated `preseed.cfg` after build for further debugging.

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

### First login
```bash
# password prompt should fail
ssh john@vm-ip   # press Enter when asked for password – should be denied
# root login should fail too
ssh root@vm-ip   # Permission denied
# check live server config
ssh john@<new-ip>   # logs in via your SSH key
sudo lvs            # shows vg0/root + vg0/swap
cat /proc/mdstat    # shows md0 (RAID1) + md1 (RAID10)
sudo sshd -T | grep -E 'passwordauthentication|challengeresponseauthentication|permitrootlogin'
# → all three report "no"
```

---

### Clean up : Stop and delete VM

```bash
virsh shutdown debian-auto 
# OR if VM do not respond 
virsh destroy debian-auto
virsh undefine debian-auto --remove-all-storage
```

---

### Customising
- Edit the public ssh key in the preseed template.
- Change vendor filter by using the `-v` flag or editing the early_command logic in the script.
- Adjust swap size or LVM layout by editing the expert_recipe in the script.
- Change GRUB menu timeout in `isolinux/txt.cfg` and `boot/grub/grub.cfg` before rebuilding.

---

### Notes
- The ISO is generic and can be used on any compatible hardware or VM.
- The build script is robust and will abort if the preseed is malformed.
- For advanced customisation, edit `build_iso.sh` and `preseed.template.cfg` as needed.

[DRY RUN] --- Generated preseed.cfg ---
... (contents here) ...
[DRY RUN] --- End of preseed.cfg ---