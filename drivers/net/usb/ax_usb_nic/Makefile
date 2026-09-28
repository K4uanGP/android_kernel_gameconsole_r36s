# SPDX-License-Identifier: GPL-2.0
#
# ASIX's own USB NIC driver v3.5.0 (ax_usb_nic), imported from
# https://github.com/g-host-one/AX88179-driver (unmodified ASIX sources,
# commit d559563). Adds AX88179A, AX88772D and AX88279 support over the
# in-tree ax88179_178a driver.
#

obj-$(CONFIG_USB_NET_AX88179_178A)	+= ax_usb_nic.o
ax_usb_nic-y := ax_main.o ax88179_178a.o ax88179a_772d.o

# Same feature set as ASIX's default Makefile
ccflags-y += -DENABLE_INT_AGGRESSIVE
ccflags-y += -DENABLE_AX88279
