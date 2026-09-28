#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Generate the USB WiFi whitelist used by the RK3326 handheld Android
# libwifi_hal (device/gameconsole/common: /vendor/etc/wifi_id_list.txt and
# /vendor/etc/modprobe.d/*) straight from the kernel build, so every
# VID:PID a built USB WiFi module can bind gets an entry and every module
# chain matches what was actually built.
#
# Usage: gen-usb-wifi-list.sh <kernel objtree> <output dir> [module dir]
#
#   <kernel objtree>  O= directory of a finished "make modules"
#   <output dir>      receives wifi_id_list.txt, modprobe.d/ and modules.txt
#   [module dir]      on-device module path (default /vendor/lib/modules)
#
# The HAL takes the first line matching a plugged in VID:PID, so drivers
# are emitted in PRIORITY order and each VID:PID only once.

set -euo pipefail

OBJ=${1:?usage: $0 <kernel objtree> <output dir> [module dir]}
OUT=${2:?usage: $0 <kernel objtree> <output dir> [module dir]}
MODDIR=${3:-/vendor/lib/modules}
PROBEDIR=/vendor/etc/modprobe.d

# Preferred driver first. Realtek vendor drivers beat rtlwifi/rtl8xxxu for
# the chips they cover, rtl8xxxu is the catch-all for the rest.
PRIORITY=(
	8821cu 88x2bu 8812au 8821au 8814au 8852bu
	8192eu 8192fu 8188eu 8188fu 8188gu
	aic8800_fdrv aic_load_fw
	mt76x2u mt76x0 mt7601u
	rt2800usb rt73usb rt2500usb
	rtl8192cu rtl8xxxu rtl8187
	ath9k_htc carl9170 ar5523
	brcmfmac mwifiex_usb
	ath6kl_usb vt6656_stage usb8xxx
	zd1211rw zd1201 p54usb at76c50x-usb rsi_usb rndis_wlan
)

# Drivers whose chip boots into a firmware loader PID and re-enumerates:
# always load the whole family, loader first.
declare -A FAMILY=(
	[aic_load_fw]="aic_load_fw aic8800_fdrv"
	[aic8800_fdrv]="aic_load_fw aic8800_fdrv"
)

# Only look at modules the current config builds (modules.order), stale
# objects from earlier configs may still sit in the objtree
declare -A MODC DEPS
while IFS= read -r ko; do
	modc=$OBJ/${ko#kernel/}
	modc=${modc%.ko}.mod.c
	[[ -f $modc ]] || continue
	name=$(basename "$modc" .mod.c)
	MODC[$name]=$modc
	DEPS[$name]=$(sed -n 's/^"depends=\(.*\)";$/\1/p' "$modc" | tr ',' ' ')
done < "$OBJ/modules.order"

# Print a module and its dependencies, dependencies first (the caller
# drops duplicates, this runs in a subshell)
resolve() {
	local m=$1 d
	for d in ${DEPS[$m]:-}; do
		resolve "$d"
	done
	echo "$m"
}

rm -rf "$OUT"
mkdir -p "$OUT/modprobe.d"
: > "$OUT/wifi_id_list.txt"

declare -A HAVE_ID ALLMODS
for drv in "${PRIORITY[@]}"; do
	[[ -n ${MODC[$drv]:-} ]] || { echo "skip $drv (not built)" >&2; continue; }

	mapfile -t chain < <(for m in ${FAMILY[$drv]:-$drv}; do resolve "$m"; done |
			     awk '!seen[$0]++')
	tag=${chain[-1]}
	probe=$tag
	for m in "${chain[@]}"; do
		ALLMODS[$m]=1
		echo "$MODDIR/$m.ko"
	done > "$OUT/modprobe.d/$probe"

	n=0
	while read -r vid pid; do
		id="$vid $pid"
		[[ -n ${HAVE_ID[$id]:-} ]] && continue
		HAVE_ID[$id]=1
		echo "$id $tag $PROBEDIR/$probe" >> "$OUT/wifi_id_list.txt"
		n=$((n + 1))
	done < <(sed -n 's/^MODULE_ALIAS("usb:v\([0-9A-F]\{4\}\)p\([0-9A-F]\{4\}\)d.*/\1 \2/p' \
			"${MODC[$drv]}" | tr 'A-F' 'a-f')
	echo "$drv: $n ids, loads ${chain[*]}" >&2
done

printf '%s.ko\n' "${!ALLMODS[@]}" | sort > "$OUT/modules.txt"
echo "total: $(wc -l < "$OUT/wifi_id_list.txt") VID:PID entries" >&2
