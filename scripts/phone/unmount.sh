#!/bin/sh -x

################################################################################
# Description: unmounts the block device previously mounted by mount_ext4.sh
# Contributors: Vivek Revankar <vivek@master-hax.com>
# Usage: ./unmount.sh
################################################################################

# namespace guard made tolerant: skip if /proc/1/ns/mnt is unreadable
# (we are reached via 'su -M' which already runs in the global namespace)
p1=$(readlink /proc/1/ns/mnt 2>/dev/null)
if [ -n "$p1" ] && [ "$(readlink /proc/self/ns/mnt)" != "$p1" ]; then
  echo "not running in global mount namespace, try elevating first"
  exit 1
fi

umount -v /mnt/pass_through/0/emulated/0/the_binding
umount -v /mnt/runtime/write/emulated/0/the_binding
umount -v /mnt/my_drive
