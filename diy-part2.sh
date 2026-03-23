#!/bin/bash

# 1. 修改默认 LAN IP 和子网掩码
# 模板文件: package/base-files/files/bin/config_generate
sed -i 's/192\.168\.[0-9]\{1,3\}\.[0-9]\{1,3\}/192.168.188.1/g' package/base-files/files/bin/config_generate
# 掩码默认就是 255.255.255.0，无需修改；如果确需修改，可添加：
# sed -i 's/255\.255\.255\.0/255.255.255.0/' package/base-files/files/bin/config_generate  # 实际已经是该值

# 2. 设置 root 密码 (加密后的 "password")
# 使用 openssl passwd -1 "password" 生成: $1$wEeHTjMS$cQz4Z5jG3L2kM8pR9vN6u/
# 将生成的哈希写入 shadow 模板
ROOT_HASH='$1$wEeHTjMS$cQz4Z5jG3L2kM8pR9vN6u/'
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" package/base-files/files/etc/shadow

# 3. 无线配置：禁用 2.4G，为 5G 设置密码（通过 uci-defaults 脚本）
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

# 4. USB 模块自动识别与 IPv6 RA 配置（通过 uci-defaults 脚本）
cat > openwrt/package/base-files/files/etc/uci-defaults/99-usb-modem-setup <<'EOF'
#!/bin/sh
# 常见蜂窝模块 MAC 前缀（可根据需要修改）
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
    echo "net.ipv6.conf.$INTERFACE.accept_ra = 2" >> /etc/sysctl.conf
    sysctl -p
    uci set network.wan.ifname="$INTERFACE"
    uci set network.wan6.ifname="$INTERFACE"
    uci commit network
    /etc/init.d/network restart
fi
exit 0
EOF
chmod +x openwrt/package/base-files/files/etc/uci-defaults/99-usb-modem-setup