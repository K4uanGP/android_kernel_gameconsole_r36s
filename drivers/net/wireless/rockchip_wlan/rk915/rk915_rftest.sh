#!/system/bin/sh

#############################################
#
# Version Information
#
#   v0.5 support continue test without reboot DUT
#   v0.4 add echo mode to check data transmission path
#   v0.3 add rx sensitivity test
#   v0.2 add Tx power config
#   v0.1 init
#
#   Authors: cmy@rock-chips.com
#
#############################################

version=0.6

dev_dir=/proc/net/rk915
tmp_file=/data/rk915_fw_info.txt

channel=1
rate=1
is_80211n=0
payload_len=1400
payload_num=-1
tx_power=15
rx=0
echo_mode=0

if [ -f "/default.prop" ];then
run_plat=android
else
run_plat=linux
killall dnsmasq dhcpcd
fi

#echo "current platform is $run_plat"

if [ -f "/sys/power/wake_lock" ];then
  echo temporary > /sys/power/wake_lock
fi

if [ -f "/system/lib/modules/rk915.ko" ];then
  ko_path=/system/lib/modules
fi

if [ -f "/vendor/lib/modules/wifi/rk915.ko" ];then
  ko_path=/vendor/lib/modules/wifi
fi

if [ -f "/vendor/lib/modules/rk915.ko" ];then
  ko_path=/vendor/lib/modules
fi

trap 'do_exit' 1 2 3 6 15

do_exit()
{
    echo ""
    echo "Exiting..."
    stop_rftest

    exit 0
}

stop_rftest()
{
    echo "Stopping..."

    echo "stop_packet_gen=0" > $dev_dir/params
    echo "stop_prod_mode=0" > $dev_dir/params
    echo "production_test=0" > $dev_dir/params
#    echo "production_test=0" > $dev_dir/params && sleep 0.5

    echo "Done."
}

shwo_usage()
{
    echo "RK915 RF test unit. Version: "$version
    echo "Usage: $0 [OPTION]..."

    echo "\ntx test:\n"

    echo "  -c\t\tSetup channel"
    echo "\t\t2.4GHz\tChannel: 1..14"

    echo "  -n\t\tEnable 802.11n"

    echo "  -r\t\tSetup rate"
    echo "\t\t802.11n\t\tRate: 0..7"
    echo "\t\tnon 802.11n\tRate: 1 2 55 11 6 9 12 18 24 36 48 54"

    echo "  -l\t\tSetup payload length"
    echo "  -s\t\tSetup how many counts of payload do you want to send, -1 means infinite package send"

    echo "  -t\t\tSetup TxPower  0..20"

    echo "\nrx sensitivity test:\n"

    echo "  -x\n\t\t 1 : Setup rx sensitivity test(fw_skip_rx_pkt_submit)\n\t\t 2 : Setup rx sensitivity test\n\t\t 3 : rx pkgs recv counts"
    echo "  -c\t\tSetup channel"

    echo "\necho test:\n"
    echo "  -e\t\tEnter ECHO mode to check data transmission path"
    echo "\n"
    echo "  -f\t\tFinish test"
    echo ""
}

while getopts "c:r:l:s:x:nt:e:f" arg
do
    case $arg in
        c)
            channel=$OPTARG
            ;;
        n)
            is_80211n=1
            ;;
        r)
            rate=$OPTARG
            ;;
        l)
            payload_len=$OPTARG
            ;;
        t)
            tx_power=$OPTARG
            ;;
        s)
            payload_num=$OPTARG
            ;;
        x)
            rx=$OPTARG
            ;;
        e)
            echo_mode=1
            ;;
        f)
            do_exit
            ;;
        *)
            shwo_usage
            exit 1
            ;;
    esac
done

if [ $rx == 4 ]; then
    rmmod rk915
    sleep 0.1
    insmod $ko_path/rk915.ko down_fw_in_probe=1 default_phy_threshold=180 lpw_no_sleep=1
    sleep 1
    production_test=0
    eval $(cat $dev_dir/params | grep "production_test" | busybox awk '
    {
        printf("production_test=%d;",$3)
    }
    ')
    if [ $production_test == 0 ]; then
        echo "production_test=1" > $dev_dir/params
        echo "fw_skip_rx_pkt_submit=1" > $dev_dir/params
    fi
    echo "Start tx cw test(fw_skip_rx_pkt_submit), Set channel: $channel"
    channel=$((channel+128))
    echo "channel: $channel"
    echo "start_prod_cw_mode=$channel" > $dev_dir/params
    exit 0
fi

if [ x"`lsmod | grep rk915`" == x ]; then
    echo "Insmod rk915 module"
    insmod $ko_path/rk915.ko down_fw_in_probe=1 default_phy_threshold=180 lpw_no_sleep=1
    sleep 0.1
fi

if [ ! -f "$dev_dir/params" ]; then
    echo "ERR: rK915 driver not loaded or init failed!"
    exit 1
fi

if [ $rx == 1 ]; then
    production_test=0
    eval $(cat $dev_dir/params | grep "production_test" | busybox awk '
    {
        printf("production_test=%d;",$3)
    }
    ')
    if [ $production_test == 0 ]; then
        echo "production_test=1" > $dev_dir/params
        echo "fw_skip_rx_pkt_submit=1" > $dev_dir/params
    fi
    echo "Start rx sensitivity test(fw_skip_rx_pkt_submit), Set channel: $channel"
    echo "start_prod_rx_mode=$channel" > $dev_dir/params
    exit 0
fi

if [ $rx == 2 ]; then
    echo "production_test=1" > $dev_dir/params
    echo "Start rx sensitivity test, Set channel: $channel"
    echo "start_prod_rx_mode=$channel" > $dev_dir/params
    exit 0
fi

if [ $rx == 3 ]; then
    fw_skip_rx_pkt_submit=0
    eval $(cat $dev_dir/params | grep "fw_skip_rx_pkt_submit" | busybox awk '
    {
        printf("fw_skip_rx_pkt_submit=%d;",$3)
    }
    ')
	if [ $fw_skip_rx_pkt_submit == 1 ]; then
        echo "fw_txrx_count_info" > $dev_dir/params
	sleep 0.1
        rx_recv_counts=0
        cat $dev_dir/fw_info > $tmp_file
        eval $(cat $tmp_file | grep "event_rx_pkt_crc_ok" | busybox awk '
        {
            printf("rx_recv_counts=%d;",$3)
        }
        ')
        echo "crc ok: $rx_recv_counts"
		rx_recv_counts_err=0
        eval $(cat $tmp_file | grep "event_rx_pkt_crc_err" | busybox awk '
        {
            printf("rx_recv_counts_err=%d;",$3)
        }
        ')
        echo "crc err: $rx_recv_counts_err"        
    else
        rx_recv_counts=0
        eval $(cat $dev_dir/mac_stats | grep "rx_packet_data_count" | busybox awk '
        {
            printf("rx_recv_counts=%d;",$3)
        }
        ')
        echo "rx recv counts: $rx_recv_counts"
        echo "rx_packet_data_count=0" > $dev_dir/params
    fi
    exit 0
fi

production_test=0
eval $(cat $dev_dir/params | grep "production_test" | busybox awk '
{
    printf("production_test=%d;",$3)
}
')
if [ $production_test == 0 ]; then
    echo "Enable production test mode"
    echo "production_test=1" > $dev_dir/params
    sleep 0.1
fi
    
echo "Start prod mode, Set channel: $channel"
if [ $echo_mode == 1 ]; then
    echo "start_prod_echo_mode=$channel" > $dev_dir/params
else
    echo "stop_packet_gen=0" > $dev_dir/params && sleep 0.1
    echo "start_prod_mode=$channel" > $dev_dir/params
fi
sleep 0.1

if [ $is_80211n == 1 ]; then
    echo "Use 802.11n"
    echo "prod_mode_rate_flag=8" > $dev_dir/params
    echo "tx_fixed_rate=-1" > $dev_dir/params
    echo "Set rate: MCS$rate"
    echo "tx_fixed_mcs_indx=$rate" > $dev_dir/params
else
    echo "prod_mode_rate_flag=0" > $dev_dir/params
    echo "tx_fixed_mcs_indx=-1" > $dev_dir/params
    echo "Set rate: $rate Mbps"
    echo "tx_fixed_rate=$rate" > $dev_dir/params
fi

echo "Set tx power: $tx_power"
echo "set_tx_power=$tx_power" > $dev_dir/params

echo "Set payload length: $payload_len"
echo "payload_length=$payload_len" > $dev_dir/params

echo "Start packet generate"
if [ $payload_num == -1 ]; then
    echo "Send infinite packets"
else
    echo "Send $payload_num packets"
fi
sleep 0.5
echo "start_packet_gen=$payload_num" > $dev_dir/params

#while true; do busybox printf "."; sleep 1; done

#stop_rftest

exit 0

