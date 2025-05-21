#!/bin/bash
#
virsh destroy debian-auto
virsh undefine debian-auto
./build_iso.sh -p r00tMe -i debian-12.10.0-amd64-netinst.iso -d "/dev/vda /dev/vdb /dev/vdc /dev/vdd"
virt-install --name debian-auto --ram 4096 --vcpus 2   --disk disk1.qcow2,bus=virtio --disk disk2.qcow2,bus=virtio   --disk disk3.qcow2,bus=virtio --disk disk4.qcow2,bus=virtio   --graphics none --console pty,target_type=serial   --cdrom debian-12.10.0-auto.iso --osinfo detect=on,require=off
