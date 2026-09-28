# SPDX-License-Identifier: GPL-2.0
#
# Realtek's own r8152 driver v2.21.4, imported from
# https://github.com/wget/realtek-r8152-linux (tag v2.21.4.20260427).
# Adds RTL8153C/D, RTL8156/8156B and RTL8157 support over the in-tree driver.
#

obj-$(CONFIG_USB_RTL8152)	+= r8152.o

# The upstream Makefile passes these for kernels older than 5.12, where
# linux/version.h does not define them yet; compatibility.h needs them.
ccflags-y += -DLINUX_VERSION_MAJOR=$(VERSION)
ccflags-y += -DLINUX_VERSION_PATCHLEVEL=$(PATCHLEVEL)
ccflags-y += -DLINUX_VERSION_SUBLEVEL=$(SUBLEVEL)
