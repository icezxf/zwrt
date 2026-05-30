#!/bin/bash

# Set default theme to luci-theme-argon
# uci set luci.main.mediaurlbase='/luci-static/argon'
# uci commit luci

# 添加旁路由防火墙
# echo "iptables -t nat -I POSTROUTING -o eth0 -j MASQUERADE" >> package/network/config/firewall/files/firewall.user
#iptables设置
# sed -i '/REDIRECT --to-ports 53/d' /etc/firewall.user
# echo "iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53" >> /etc/firewall.user
# echo "iptables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53" >> /etc/firewall.user

#设置fstab开启热插拔自动挂载
# uci set fstab.@global[0].anon_mount=1
# uci commit fstab

# 配置nps 
#uci set nps.@nps[0].enabled='0'
#uci set nps.@nps[0].server_addr='127.0.0.1'
#uci set nps.@nps[0].vkey='kbEwlNnKytsg28gfvseCmP5pU8Vqo0c1rrlHfsi3Q'
#uci commit nps
# dnsmasq
#uci set dhcp.@dnsmasq[0].rebind_protection='0'
#uci set dhcp.@dnsmasq[0].localservice='0'
#uci set dhcp.@dnsmasq[0].nonwildcard='0'
#if ! grep -Eq '223.5.5.5' /etc/config/dhcp;then
#  uci add_list dhcp.@dnsmasq[0].server='223.5.5.5#53'
#fi
#uci commit dhcp

# Disable IPV6 ula prefix
# sed -i 's/^[^#].*option ula/#&/' /etc/config/network

# Check file system during boot
# uci set fstab.@global[0].check_fs=1
# uci commit fstab
#!/bin/sh

#!/bin/sh

# ==========================================
# OpenWrt 首次启动初始化脚本 (uci-defaults)
# ==========================================

# 1. 完善设置 LAN 口网络参数
# 强制设为静态IP模式，防止被上级路由DHCP干扰
uci set network.lan.proto='static'
# 设置目标管理IP地址
uci set network.lan.ipaddr='192.168.2.3'
# 显式指定标准子网掩码，确保万无一失
uci set network.lan.netmask='255.255.255.0'
uci commit network

# 2. 智能遍历并分别设置 2.4G 和 5G 无线设备
for radio in $(uci show wireless | grep '=wifi-device' | cut -d '.' -f 2); do
    # 获取当前无线设备的频段信息 (band)
    band=$(uci get wireless.$radio.band 2>/dev/null)
    
    # 针对 2.4G 频段的无线设备进行配置
    if [ "$band" = "2g" ]; then
        uci set wireless.default_${radio}.ssid='openwrt-2.4g'
        uci set wireless.default_${radio}.key='gpsgpsgp'
        uci set wireless.${radio}.disabled='0'
    fi
    
    # 针对 5G 频段的无线设备进行配置
    if [ "$band" = "5g" ]; then
        uci set wireless.default_${radio}.ssid='openwrt-5g'
        uci set wireless.default_${radio}.key='gpsgpsgp'
        uci set wireless.${radio}.disabled='0'
    fi
done
uci commit wireless

# 3. 退出并返回成功状态码 0
exit 0
