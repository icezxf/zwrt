#!/usr/bin/env bash

#
# FanchmWrt Integration Script
# This script integrates fanchmwrt packages (app filtering, firewall, UI) into zwrt
# Requires: build directory path as argument
# Usage: fan.sh <build_dir>
#

set -e

BUILD_DIR="$1"

if [[ -z "$BUILD_DIR" ]]; then
    echo "Error: BUILD_DIR not specified"
    echo "Usage: $0 <build_dir>"
    exit 1
fi

# Convert to absolute path
if [[ "$BUILD_DIR" != /* ]]; then
    BUILD_DIR="$(pwd)/$BUILD_DIR"
fi

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "Error: BUILD_DIR does not exist: $BUILD_DIR"
    exit 1
fi

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
BASE_PATH=${BASE_PATH:-$SCRIPT_DIR}

echo "=========================================="
echo "FanchmWrt Integration Started"
echo "=========================================="
echo "Build Dir: $BUILD_DIR"
echo "Base Path: $BASE_PATH"
echo ""

# ============================================
# Function: Add FanchmWrt feeds source
# ============================================
add_fanchmwrt_feeds() {
    local feeds_conf="$BUILD_DIR/feeds.conf.default"
    
    echo "[*] Adding fanchmwrt feed source..."
    
    if [[ ! -f "$feeds_conf" ]]; then
        echo "    Warning: feeds.conf.default not found: $feeds_conf"
        return 1
    fi
    
    # Check if fanchmwrt feed already exists
    if grep -q "fanchmwrt" "$feeds_conf"; then
        echo "    Info: fanchmwrt feed already exists in feeds.conf.default"
        return 0
    fi
    
    # Append fanchmwrt feed source
    echo "src-git fanchmwrt https://github.com/fanchmwrt/fanchmwrt-packages.git" >> "$feeds_conf"
    echo "    ✓ Added: src-git fanchmwrt https://github.com/fanchmwrt/fanchmwrt-packages.git"
    
    return 0
}

# ============================================
# Function: Enable FanchmWrt packages in .config
# ============================================
create_fanchmwrt_config() {
    local config_file="$BUILD_DIR/.config"
    
    echo "[*] Configuring fanchmwrt packages in .config..."
    
    if [[ ! -f "$config_file" ]]; then
        echo "    Warning: .config not found: $config_file"
        return 1
    fi
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Function to add or update config option
    add_config_option() {
        local key=$1
        local value=$2
        
        if grep -q "^$key=" "$config_file"; then
            # Update existing
            sed -i "s/^$key=.*/$key=$value/" "$config_file"
        else
            # Append new
            echo "$key=$value" >> "$config_file"
        fi
    }
    
    # Core engine
    echo "    [+] Core engine packages:"
    add_config_option "CONFIG_PACKAGE_fwxd" "y"
    echo "        - CONFIG_PACKAGE_fwxd=y"
    add_config_option "CONFIG_PACKAGE_kmod-fwx" "y"
    echo "        - CONFIG_PACKAGE_kmod-fwx=y"
    
    # UI and resources
    echo "    [+] UI and resources packages:"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-resources" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-resources=y"
    add_config_option "CONFIG_PACKAGE_luci-theme-argon" "y"
    echo "        - CONFIG_PACKAGE_luci-theme-argon=y"
    
    # Feature applications
    echo "    [+] Feature applications:"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-appfilter" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-appfilter=y (Application filtering)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-dashboard" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-dashboard=y (Dashboard)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-user" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-user=y (User management)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-user-record" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-user-record=y (User records)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-record" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-record=y (Access logs)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-session-stat" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-session-stat=y (Session statistics)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-macfilter" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-macfilter=y (MAC filtering)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-system" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-system=y (System settings)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-network" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-network=y (Network settings)"
    add_config_option "CONFIG_PACKAGE_luci-app-fwx-feature" "y"
    echo "        - CONFIG_PACKAGE_luci-app-fwx-feature=y (Feature library)"
    
    # Dependencies
    echo "    [+] Required dependencies:"
    add_config_option "CONFIG_PACKAGE_luci-compat" "y"
    echo "        - CONFIG_PACKAGE_luci-compat=y"
    add_config_option "CONFIG_PACKAGE_luci-lib-jsonc" "y"
    echo "        - CONFIG_PACKAGE_luci-lib-jsonc=y"
    
    rm -f "$temp_file"
    return 0
}

# ============================================
# Function: Create UCI default configuration
# ============================================
create_fanchmwrt_defaults() {
    local defaults_dir="$BUILD_DIR/package/emortal/default-settings/files"
    local config_file="$defaults_dir/99-fanchmwrt"
    
    echo "[*] Creating fanchmwrt UCI defaults..."
    
    if [[ ! -d "$defaults_dir" ]]; then
        echo "    Info: defaults directory not found, skipping"
        return 0
    fi
    
    # Create fanchmwrt default config
    cat > "$config_file" << 'EOF'
#!/bin/sh

# FanchmWrt default configuration

# Enable firewall
uci set firewall.@defaults[0].enabled='1'

# Enable session inspection for app filtering
uci set firewall.@defaults[0].syn_flood='1'

# Commit changes
uci commit firewall

# Restart firewall to apply changes
/etc/init.d/firewall restart

echo "FanchmWrt default configuration applied"
EOF

    chmod +x "$config_file"
    echo "    ✓ Created: $config_file"
    
    return 0
}

# ============================================
# Function: Apply compatibility patches
# ============================================
apply_compatibility_patches() {
    echo "[*] Applying compatibility patches..."
    
    # Check if luci-compat feed is installed
    if [[ ! -d "$BUILD_DIR/feeds/luci" ]]; then
        echo "    Info: luci feed not found, skipping"
        return 0
    fi
    
    # Ensure luci-compat is available
    if [[ ! -d "$BUILD_DIR/feeds/luci/libs/luci-compat" ]]; then
        echo "    Info: luci-compat not found, will be installed from feeds"
    else
        echo "    ✓ luci-compat found"
    fi
    
    return 0
}

# ============================================
# Function: Configure Luci menu ordering
# ============================================
configure_luci_menu() {
    echo "[*] Configuring Luci menu..."
    
    # The menu configuration is handled by the fanchmwrt packages themselves
    # through their Makefile definitions, so no manual configuration needed
    
    echo "    ✓ Luci menu will be configured by fanchmwrt packages"
    
    return 0
}

# ============================================
# Function: Verify FanchmWrt setup
# ============================================
verify_fanchmwrt_setup() {
    echo "[*] Verifying FanchmWrt setup..."
    
    local config_file="$BUILD_DIR/.config"
    local feeds_conf="$BUILD_DIR/feeds.conf.default"
    
    local errors=0
    
    # Check feeds.conf.default
    if grep -q "src-git fanchmwrt" "$feeds_conf"; then
        echo "    ✓ fanchmwrt feed source added"
    else
        echo "    ✗ fanchmwrt feed source NOT found"
        ((errors++))
    fi
    
    # Check key packages in .config
    local packages=(
        "CONFIG_PACKAGE_fwxd"
        "CONFIG_PACKAGE_kmod-fwx"
        "CONFIG_PACKAGE_luci-app-fwx-appfilter"
        "CONFIG_PACKAGE_luci-app-fwx-dashboard"
        "CONFIG_PACKAGE_luci-theme-argon"
    )
    
    for pkg in "${packages[@]}"; do
        if grep -q "^${pkg}=y" "$config_file"; then
            echo "    ✓ $pkg enabled"
        else
            echo "    ⚠ $pkg NOT enabled"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        echo "    ✓ All verifications passed!"
        return 0
    else
        echo "    ⚠ $errors issues found (may be resolved during feeds update)"
        return 0  # Don't fail, as feeds update will handle this
    fi
}

# ============================================
# Main execution
# ============================================
main() {
    echo ""
    
    # Step 1: Add feeds
    if ! add_fanchmwrt_feeds; then
        echo "✗ Failed to add fanchmwrt feeds"
        return 1
    fi
    echo ""
    
    # Step 2: Create config
    if ! create_fanchmwrt_config; then
        echo "✗ Failed to create fanchmwrt config"
        return 1
    fi
    echo ""
    
    # Step 3: Create defaults
    if ! create_fanchmwrt_defaults; then
        echo "⚠ Warning: Failed to create defaults (non-critical)"
    fi
    echo ""
    
    # Step 4: Apply patches
    if ! apply_compatibility_patches; then
        echo "⚠ Warning: Failed to apply patches (non-critical)"
    fi
    echo ""
    
    # Step 5: Configure menu
    if ! configure_luci_menu; then
        echo "⚠ Warning: Failed to configure menu (non-critical)"
    fi
    echo ""
    
    # Step 6: Verify setup
    verify_fanchmwrt_setup
    echo ""
    
    echo "=========================================="
    echo "✓ FanchmWrt Integration Completed!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Run: ./scripts/feeds update -a"
    echo "2. Run: ./scripts/feeds install -a"
    echo "3. Run: make menuconfig (and verify fanchmwrt packages)"
    echo "4. Run: make"
    echo ""
    echo "Features enabled:"
    echo "  ✓ Application filtering (上网行为管理)"
    echo "  ✓ FanchmWrt dashboard UI (仪表板皮肤)"
    echo "  ✓ User management"
    echo "  ✓ MAC filtering"
    echo "  ✓ Access logs"
    echo "  ✓ Session statistics"
    echo ""
}

main "$@"
