#!/bin/bash

# ======================== 进入源码目录（可选，路径已是 openwrt 前缀，无需 cd） ========================

# 1. 修改默认 LAN IP 为 192.168.188.1（掩码已是 255.255.255.0，无需改动）
sed -i 's/192.168.1.1/192.168.188.1/g' openwrt/package/base-files/files/bin/config_generate

# 2. 设置 root 密码为 "password"（生成加密哈希）
#ROOT_HASH='$1$wEeHTjMS$cQz4Z5jG3L2kM8pR9vN6u/'
#sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" openwrt/package/base-files/files/etc/shadow

