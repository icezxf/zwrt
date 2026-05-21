#!/bin/sh

# AdGuard Home DHCP 租约文件路径
ADGUARD_WORK_DIR=$(awk '/option workdir/ { gsub(/\047/, "", $3); print $3 }' /etc/config/AdGuardHome)
ADGUARD_DHCP_FILE="$ADGUARD_WORK_DIR/data/leases.json"
LEASES_TMP_FILE="/tmp/dhcp.leases"

# 检查是否安装了 jq
if ! command -v jq &>/dev/null; then
    echo "jq is not installed. Please install jq to parse JSON data."
    exit 1
fi

# 检查 DHCP 数据文件是否存在
if [ ! -f "$ADGUARD_DHCP_FILE" ]; then
    echo "No DHCP data available"
    exit 1
fi

# 获取当前时间的 Unix 时间戳
current_time=$(date -u +%s)

# 清空现有的租约文件
echo "" > $LEASES_TMP_FILE

# 解析 AdGuard Home 租约文件并写入到 OpenWrt 格式的租约文件
leases=$(jq -c '.leases[]' "$ADGUARD_DHCP_FILE")
echo "$leases" | while read -r lease; do
    # 提取字段
    expires=$(echo "$lease" | jq -r '.expires')
    mac=$(echo "$lease" | jq -r '.mac')
    ip=$(echo "$lease" | jq -r '.ip')
    hostname=$(echo "$lease" | jq -r '.hostname')

    # 删除 ISO 8601 日期中的 'T' 和 'Z'
    expires_sanitized=$(echo "$expires" | sed 's/T/ /;s/Z//')

    # 将过期时间转换为 Unix 时间戳
    expire_timestamp=$(date -u -d "$expires_sanitized" +%s)

    # 检查租约是否过期
    if [ "$expire_timestamp" -ge "$current_time" ]; then
        # 写入租约到文件中
        echo "$expire_timestamp $mac $ip $hostname *" >> $LEASES_TMP_FILE
    fi
done

echo "DHCP 租约已更新到 $LEASES_TMP_FILE"