# AIC8800 USB WiFi (radxa-pkg/aic8800, src/USB/driver_fw/drivers/aic8800)
obj-$(CONFIG_AIC_LOADFW_SUPPORT)    += aic_load_fw/
obj-$(CONFIG_AIC8800_WLAN_SUPPORT) += aic8800_fdrv/

########## config option ##########
export CONFIG_USE_FW_REQUEST = n
export CONFIG_PREALLOC_RX_SKB = y
export CONFIG_PREALLOC_TXQ = y
export CONFIG_WOWLAN = n

########## platform ##########
# Generic platform: per-chip firmware subdirectories under the default
# firmware path, which points at /vendor/firmware for Android
export CONFIG_PLATFORM_ROCKCHIP = n
export CONFIG_PLATFORM_ALLWINNER = n
export CONFIG_PLATFORM_AMLOGIC = n
export CONFIG_PLATFORM_HI = n
export CONFIG_PLATFORM_UBUNTU = y
