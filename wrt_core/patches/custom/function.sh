#!/bin/bash

config_file=".config"
CUSTOM_PATCH_DIR="$GITHUB_WORKSPACE/wrt_core/patches/custom"
BASE_PATH=$1

CUSTOM_OP=https://github.com/caiwx86/small-packages
CUSTOM_OPP=https://github.com/kenzok8/jell
CUSTOM_OP_BRANCH=main

if [[ -d $BASE_PATH ]]; then
   BASE_PATH=$(cd $BASE_PATH && pwd)
   echo "BASE_PATH: $BASE_PATH"
else
   C_PWD=$(pwd)
   echo "$BASE_PATH 不存在, 当前路径: $C_PWD"
fi

function cat_kernel_config() {
  if [ -f $1 ]; then
    cat >> $1 <<EOF
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_CGROUPS=y
CONFIG_KPROBES=y
CONFIG_NET_INGRESS=y
CONFIG_NET_EGRESS=y
CONFIG_NET_SCH_INGRESS=m
CONFIG_NET_CLS_BPF=m
CONFIG_NET_CLS_ACT=y
CONFIG_BPF_STREAM_PARSER=y
CONFIG_DEBUG_INFO=y
# CONFIG_DEBUG_INFO_REDUCED is not set
CONFIG_DEBUG_INFO_BTF=y
CONFIG_KPROBE_EVENTS=y
CONFIG_BPF_EVENTS=y

CONFIG_NET_SCH_BPF=y
CONFIG_SCHED_CLASS_EXT=y
CONFIG_PROBE_EVENTS_BTF_ARGS=y
CONFIG_IMX_SCMI_MISC_DRV=n
CONFIG_ARM64_CONTPTE=y

CONFIG_PERSISTENT_HUGE_ZERO_FOLIO=n
CONFIG_NO_PAGE_MAPCOUNT=n
CONFIG_ARM64_BRBE=y
EOF
    echo "cat_kernel_config to $1 done"
  fi
}

function cat_ebpf_config() {
#ebpf相关
  cat >> $1 <<EOF
#eBPF
CONFIG_DEVEL=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y

CONFIG_KERNEL_TRANSPARENT_HUGEPAGE=y
# CONFIG_KERNEL_TRANSPARENT_HUGEPAGE_ALWAYS is not set
CONFIG_KERNEL_TRANSPARENT_HUGEPAGE_MADVISE=y
# CONFIG_KERNEL_TRANSPARENT_HUGEPAGE_NEVER is not set
EOF
}

function kernel_version() {
  echo $(sed -n 's/^KERNEL_PATCHVER:=\(.*\)/\1/p' target/linux/qualcommax/Makefile)
}

function set_kernel_size() {
  #修改jdc ax1800 pro 的内核大小为12M
  image_file='./target/linux/qualcommax/image/ipq60xx.mk'
  sed -i "/^define Device\/emmc-common/,/^endef/ s/KERNEL_SIZE := 6144k/KERNEL_SIZE := 12288k/" $image_file
  sed -i "/^define Device\/nand-common/,/^endef/ s/^endef/\tKERNEL_SIZE := 8192k\nendef/" $image_file
  sed -i "/^define Device\/jdcloud_re-ss-01/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/jdcloud_re-cs-02/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/jdcloud_re-cs-07/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
#  sed -i "/^define Device\/redmi_ax5-jdcloud/,/^endef/ s/^endef/  KERNEL_SIZE := 12288k\nendef/" $image_file
  sed -i "/^define Device\/linksys_mr/,/^endef/ { /KERNEL_SIZE := 8192k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/link_nn6000-common/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
}

#开启内存回收补丁
function enable_skb_recycler() {
  cat >> $1 <<EOF
CONFIG_KERNEL_SKB_RECYCLER=y
CONFIG_KERNEL_SKB_RECYCLER_MULTI_CPU=y
EOF
}

function generate_config() {
  echo "执行generate_config()"
  #配置文件不存在
  if [[ ! -f $config_file ]]; then
      echo $config_file 文件不存在
      exit
  else
      echo "# function.sh ..." >> $config_file
  fi

  #默认机型为ipq60xx
  local target='ipq60xx'

  #增加ebpf
  cat_ebpf_config $config_file
  enable_skb_recycler $config_file
  set_kernel_size
  #增加内核选项
  cat_kernel_config "target/linux/qualcommax/${target}/config-default"
}

# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ $BASE_PATH/package 
  cd $BASE_PATH && rm -rf $repodir
}

# 删除指定软件包
function remove_package() {
   packages="$@"
   for package in $packages; do 
      pkg_path=$(find . -type d -name "$package")
      if [[ ! "$pkg_path" == "" ]]; then
         rm -rvf $pkg_path
      fi
   done
}

# 查找软件包中文件并替换
# $1: 文件夹路径
# $2: 文件匹配字符串
function find_replace() {
    file_path=$1
    package=$2
    pkg_path=$(find . -type d | grep "$package$")
    if [[ ! "$pkg_path" == "" ]]; then
        for dir_path in $pkg_path; do 
          cp -rv $file_path $pkg_path
          echo "$file_path 文件复制到 $pkg_path 成功"
        done
    fi 
}

function add_daed() {
  # 删除不用插件
  remove_package daed luci-app-daed
  # 添加额外插件
  git_sparse_clone $CUSTOM_OP_BRANCH $CUSTOM_OP \
      luci-app-daed vmlinux-btf daed
  
  #修复daed/Makefile
  #rm -rf luci-app-daed/daed/Makefile && cp -r $GITHUB_WORKSPACE/patches/daed/Makefile luci-app-daed/daed/
  sed -i 's/pnpm install ; \\/pnpm install --no-frozen-lockfile ; \\/g'  $BASE_PATH/package/daed/Makefile
  sed -i 's|github.com/daeuniverse/quic-go|github.com/olicesx/quic-go|g' $BASE_PATH/package/daed/Makefile
  sed -i 's|/run/i\\  procd_set_param|/procd_set_param command/i \\\tprocd_set_param|g' $BASE_PATH/package/daed/luci-app-daed/root/etc/init.d/luci_daed
  #cat luci-app-daed/daed/Makefile
  # 添加daed配置
  echo "CONFIG_PACKAGE_luci-app-daed=y" >> $config_file 
}

function set_theme() {
  remove_package luci-app-argon-config luci-theme-argon 
  git_sparse_clone openwrt-25.12 https://github.com/sbwml/luci-theme-argon \
     luci-app-argon-config luci-theme-argon 
  # 添加argon主题配置
  echo "CONFIG_PACKAGE_luci-app-argon-config=y" >> $config_file
  echo "CONFIG_PACKAGE_luci-theme-argon=y" >> $config_file

  argon_css_file=$(find ./package/luci-theme-argon/ -type f -name "cascade.css")
  #修改字体
  sed -i "/^.main .main-left .nav li a {/,/^}/ { /font-weight: bolder/d }" $argon_css_file
  sed -i '/^\[data-page="admin-system-opkg"\] #maincontent>.container {/,/}/ s/font-weight: 600;/font-weight: normal;/' $argon_css_file

  if [ -d "package/luci-theme-argon" ]; then
     find "package/luci-theme-argon" -type f -name "cascade*" -exec sed -i 's/--bar-bg/--primary/g' {} \;
  fi

}
  
function add_dae() {
  remove_package dae luci-app-dae
  git_sparse_clone $CUSTOM_OP_BRANCH $CUSTOM_OP \
      dae luci-app-dae
  echo "CONFIG_PACKAGE_luci-app-dae=y" >> $config_file
}

function add_geodata() {
  remove_package v2ray-geodata
  cp -rv $CUSTOM_PATCH_DIR/v2ray-geodata ./package/
  echo "CONFIG_PACKAGE_v2ray-geodata-updater=y" >> $config_file
  echo "CONFIG_PACKAGE_v2ray-geodata=y" >> $config_file
}

function add_partexp() {
  remove_package luci-app-partexp
  git_sparse_clone $CUSTOM_OP_BRANCH $CUSTOM_OP \
      luci-app-partexp
  echo "CONFIG_PACKAGE_luci-app-partexp=y" >> $config_file
}

function add_timecontrol() {
  remove_package luci-app-timecontrol
  git_sparse_clone $CUSTOM_OPP_BRANCH $CUSTOM_OP \
      luci-app-timecontrol
  echo "CONFIG_PACKAGE_luci-app-timecontrol=y" >> $config_file
}

function add_momo() {
  remove_package momo luci-app-momo
  git_sparse_clone $CUSTOM_OP_BRANCH $CUSTOM_OP \
      momo luci-app-momo
  echo "CONFIG_PACKAGE_luci-app-momo=y" >> $config_file
}

function add_openlist() {
  remove_package openlist luci-app-openlist
  git_sparse_clone $CUSTOM_OP_BRANCH $CUSTOM_OP \
       openlist2 luci-app-openlist2
  echo "CONFIG_PACKAGE_luci-app-openlist2=y" >> $config_file
}

function add_ddns() {
  git_sparse_clone $CUSTOM_OP_BRANCH $CUSTOM_OP \
       ddns-go luci-app-ddns-go
  echo "CONFIG_PACKAGE_luci-app-ddns-go=y" >> $config_file
}

function add_cifs() {
  git_sparse_clone $CUSTOM_OP_BRANCH $CUSTOM_OPP \
       luci-app-cifs-mount
  echo "CONFIG_PACKAGE_luci-app-cifs-mount=y" >> $config_file
}

function add_lucinginx() {
  git_sparse_clone $CUSTOM_OP_BRANCH $CUSTOM_OPP \
       luci-app-nginx
  echo "CONFIG_PACKAGE_luci-app-nginx=y" >> $config_file
}

function add_nginxmanager() {
  local repo="https://github.com/Vera2016/luci-app-nginx-manager"
  local branch="main"
  
  # 克隆
  git clone --depth=1 -b "$branch" "$repo"
  
  # 自动获取克隆下来的文件夹名（去掉 URL 后缀）
  # 这样不管仓库叫什么，都能准确找到文件夹
  local folder_name=$(basename "$repo")
  
  # 移动（使用变量代替死记硬背的名字）
  mv -f "$folder_name" "$BASE_PATH/package/"
  
  # 写入配置
  echo "CONFIG_PACKAGE_luci-app-nginx-manager=y" >> $config_file
}

function add_podman() {
  local repo="https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman"
  local branch="main"
  
  # 克隆
  git clone --depth=1 -b "$branch" "$repo"
  
  # 自动获取克隆下来的文件夹名（去掉 URL 后缀）
  # 这样不管仓库叫什么，都能准确找到文件夹
  local folder_name=$(basename "$repo")
  
  # 移动（使用变量代替死记硬背的名字）
  mv -f "$folder_name" "$BASE_PATH/package/"
  
  # 写入配置
  echo "CONFIG_PACKAGE_luci-app-podman=y" >> $config_file
  echo "CONFIG_PACKAGE_podman=y" >> $config_file

}

function add_other_package() {
  echo "添加其他通插件"
  # add other package
  #impitool
  echo "CONFIG_PACKAGE_luci-app-emby=y" >> $config_file
  echo "CONFIG_PACKAGE_luci-app-acme=y" >> $config_file
  echo #"CONFIG_PACKAGE_luci-app-ddns-go=y" >> $config_file
}

function add_defaults_settings() {
  # 添加默认设置脚本
  if [[ ! -d "files/etc/uci-defaults" ]]; then
    mkdir -p files/etc/uci-defaults
  fi
  cp $CUSTOM_PATCH_DIR/init-settings.sh files/etc/uci-defaults/99-init-settings
}

# 主要执行程序
# 解决配置文件未换行问题
echo "" >> $config_file
add_dae
#add_daed
add_geodata
#add_timecontrol
set_theme
#add_partexp
#add_momo
add_openlist
#add_ddns
add_cifs
add_lucinginx
add_nginxmanager
add_podman
add_other_package
add_defaults_settings
generate_config && cat $config_file
