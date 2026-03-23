#!/bin/bash

# ======================== 进入源码目录（可选，路径已是 openwrt 前缀，无需 cd） ========================

# 1. 修改默认 LAN IP 为 192.168.188.1（掩码已是 255.255.255.0，无需改动）
sed -i 's/192\.168\.[0-9]\{1,3\}\.[0-9]\{1,3\}/192.168.188.1/g' openwrt/package/base-files/files/bin/config_generate

# 2. 设置 root 密码为 "password"（生成加密哈希）
ROOT_HASH='$1$wEeHTjMS$cQz4Z5jG3L2kM8pR9vN6u/'
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" openwrt/package/base-files/files/etc/shadow

# 3. 确保 LAN 接口启用 IPv6 分配（/64 前缀）
# 替换已存在的 ip6assign 行，如果不存在则添加
if grep -q "option ip6assign" openwrt/package/base-files/files/etc/config/network; then
    sed -i '/config interface '\''lan'\''/,/^$/ s/option ip6assign.*/option ip6assign '\''64'\''/' openwrt/package/base-files/files/etc/config/network
else
    sed -i '/config interface '\''lan'\''/a \    option ip6assign '\''64'\''' openwrt/package/base-files/files/etc/config/network
fi

# 4. 修改 DHCP 配置，将 LAN 的 IPv6 服务改为 server 模式
# 替换已存在的选项，如果不存在则添加
for opt in dhcpv6 ra ra_management ndp; do
    if grep -q "option $opt" openwrt/package/base-files/files/etc/config/dhcp; then
        case $opt in
            dhcpv6) sed -i '/config dhcp '\''lan'\''/,/^$/ s/option dhcpv6.*/option dhcpv6 '\''server'\''/' openwrt/package/base-files/files/etc/config/dhcp ;;
            ra)     sed -i '/config dhcp '\''lan'\''/,/^$/ s/option ra.*/option ra '\''server'\''/' openwrt/package/base-files/files/etc/config/dhcp ;;
            ra_management) sed -i '/config dhcp '\''lan'\''/,/^$/ s/option ra_management.*/option ra_management '\''1'\''/' openwrt/package/base-files/files/etc/config/dhcp ;;
            ndp)    sed -i '/config dhcp '\''lan'\''/,/^$/ s/option ndp.*/option ndp '\''1'\''/' openwrt/package/base-files/files/etc/config/dhcp ;;
        esac
    else
        case $opt in
            dhcpv6)        sed -i '/config dhcp '\''lan'\''/a \    option dhcpv6 '\''server'\''' openwrt/package/base-files/files/etc/config/dhcp ;;
            ra)            sed -i '/config dhcp '\''lan'\''/a \    option ra '\''server'\''' openwrt/package/base-files/files/etc/config/dhcp ;;
            ra_management) sed -i '/config dhcp '\''lan'\''/a \    option ra_management '\''1'\''' openwrt/package/base-files/files/etc/config/dhcp ;;
            ndp)           sed -i '/config dhcp '\''lan'\''/a \    option ndp '\''1'\''' openwrt/package/base-files/files/etc/config/dhcp ;;
        esac
    fi
done

# 5. 创建 uci-defaults 目录（确保存在）
mkdir -p openwrt/package/base-files/files/etc/uci-defaults

# 6. 无线配置脚本：禁用 2.4G，设置 5G 密码为 a1391959853
cat > openwrt/package/base-files/files/etc/uci-defaults/99-wifi-setup <<'EOF'
#!/bin/sh
# 禁用所有 2.4G 无线设备
for radio in $(uci show wireless | grep "=wifi-device" | cut -d. -f2); do
    hwmode=$(uci get wireless.$radio.hwmode)
    case "$hwmode" in
        "11g"|"11n")
            uci set wireless.$radio.disabled=1
            ;;
    esac
done
# 为所有启用的无线接口设置密码
for iface in $(uci show wireless | grep "=wifi-iface" | cut -d. -f2); do
    device=$(uci get wireless.$iface.device)
    disabled=$(uci get wireless.$device.disabled 2>/dev/null)
    if [ "$disabled" != "1" ]; then
        uci set wireless.$iface.encryption='psk2'
        uci set wireless.$iface.key='a1391959853'
    fi
done
uci commit wireless
exit 0
EOF
chmod +x openwrt/package/base-files/files/etc/uci-defaults/99-wifi-setup

# 7. USB 模块自动识别与 IPv6 RA 配置脚本
cat > openwrt/package/base-files/files/etc/uci-defaults/99-usb-modem-setup <<'EOF'
#!/bin/sh
# 常见蜂窝模块 MAC 前缀（可根据实际模块修改）
MODEM_MACS="80:5F:6C 0C:5B:8F 4C:79:6E 8C:18:D9 00:1E:10 00:A0:C6 68:95:9D"
sleep 5
INTERFACE=""
for iface in $(ls /sys/class/net/ | grep -v lo); do
    mac=$(cat /sys/class/net/$iface/address 2>/dev/null | tr '[:upper:]' '[:lower:]')
    for prefix in $MODEM_MACS; do
        if echo "$mac" | grep -q "^$prefix"; then
            INTERFACE=$iface
            break 2
        fi
    done
done
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(ip link show | grep -o 'usb[0-9]' | head -1)
fi
if [ -n "$INTERFACE" ]; then
    # 设置 accept_ra
    echo "net.ipv6.conf.$INTERFACE.accept_ra = 2" >> /etc/sysctl.conf
    sysctl -p
    # 修改网络配置，将 wan/wan6 绑定到此接口
    uci set network.wan.ifname="$INTERFACE"
    uci set network.wan6.ifname="$INTERFACE"
    uci commit network
    /etc/init.d/network restart
fi
exit 0
EOF
chmod +x openwrt/package/base-files/files/etc/uci-defaults/99-usb-modem-setup