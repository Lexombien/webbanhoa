#!/bin/bash

# =================================================================
# OLS AUTO CONFIGURATOR - "MẠNH TAY" (V3 - Fix File Name)
# =================================================================

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}   OLS AUTO CONFIG - HARDCORE MODE (V3)            ${NC}"
echo -e "${BLUE}===================================================${NC}"

OLS_ROOT="/usr/local/lsws"
CONF_DIR="$OLS_ROOT/conf/vhosts"

echo -e "${YELLOW}[?] Nhập tên miền của bạn (VD: lemyloi.work.gd):${NC}"
read -r DOMAIN_NAME

if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}❌ Lỗi: Chưa nhập tên miền!${NC}"
    exit 1
fi

# Hàm tìm file config thông minh hơn
find_config() {
    local TARGET_NAME=$1
    local DIR_PATH="$CONF_DIR/$TARGET_NAME"

    # 1. Chuẩn OLS (vhconf.conf)
    if [ -f "$DIR_PATH/vhconf.conf" ]; then
        echo "$DIR_PATH/vhconf.conf"
        return
    fi
    
    # 2. Chuẩn CyberPanel (vhost.conf)
    if [ -f "$DIR_PATH/vhost.conf" ]; then
        echo "$DIR_PATH/vhost.conf"
        return
    fi
    
    # 3. Chuẩn Custom (tên file = tên domain.conf)
    if [ -f "$DIR_PATH/$TARGET_NAME.conf" ]; then
        echo "$DIR_PATH/$TARGET_NAME.conf"
        return
    fi

    # 4. Tìm bất kỳ file .conf nào trong thư mục đó (trừ file backup)
    # Lấy file .conf đầu tiên tìm thấy
    local ANY_CONF=$(find "$DIR_PATH" -maxdepth 1 -name "*.conf" | head -n 1)
    if [ ! -z "$ANY_CONF" ]; then
        echo "$ANY_CONF"
        return
    fi
}

VHOST_CONF=$(find_config "$DOMAIN_NAME")

if [ -z "$VHOST_CONF" ]; then
    echo -e "${RED}❌ Không tìm thấy config cho domain '$DOMAIN_NAME'.${NC}"
    echo -e "\n🔍 Đang liệt kê các Virtual Host hiện có:"
    ls -1 "$CONF_DIR"
    
    echo -e "${YELLOW}[?] Nhập tên thư mục VHOST:${NC}"
    read -r VHOST_DIR_NAME
    
    if [ -z "$VHOST_DIR_NAME" ]; then
        exit 1
    fi
    
    VHOST_CONF=$(find_config "$VHOST_DIR_NAME")
    
    if [ -z "$VHOST_CONF" ]; then
        echo -e "${RED}❌ Vẫn không tìm thấy file .conf nào trong folder đó!${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Đã tìm thấy file cấu hình: $VHOST_CONF${NC}"

# BACKUP
cp "$VHOST_CONF" "$VHOST_CONF.bak_$(date +%s)"

# XÁC ĐỊNH SLL
SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
SSL_BLOCK=""

if [ -f "$SSL_KEY" ]; then
    SSL_BLOCK="
vhssl  {
  keyFile                 $SSL_KEY
  certFile                $SSL_CERT
  certChain               1
  sslProtocol             24
  enableSpdy              1
  enableQuic              1
}"
else
    # Giữ nguyên SSL cũ nếu tìm thấy trong file cũ
    # (Đơn giản là warn user thôi, tránh làm hỏng SSL tự tạo)
    echo "⚠️  Không thấy SSL Let's Encrypt. Web sẽ chạy HTTP hoặc dùng SSL cũ."
fi

# GHI ĐÈ FILE CONFIG
# QUAN TRỌNG: $VH_ROOT là biến nội bộ của OLS
# docRoot trỏ về dist
# context /api/ trỏ về 3001
# context /uploads/ trỏ về folder uploads

cat > "$VHOST_CONF" <<EOF
docRoot                   \$VH_ROOT/html/dist
vhDomain                  $DOMAIN_NAME
vhAliases                 www.$DOMAIN_NAME
adminEmails               admin@$DOMAIN_NAME
enableGzip                1
enableIpGeo               1

index  {
  useServer               0
  indexFiles              index.html
}

errorlog \$VH_ROOT/logs/$DOMAIN_NAME.error_log {
  useServer               0
  logLevel                ERROR
  rollingSize             10M
}

accesslog \$VH_ROOT/logs/$DOMAIN_NAME.access_log {
  useServer               0
  logFormat               "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\""
  logHeaders              5
  rollingSize             10M
  keepDays                30
  compressArchive         1
}

scripthandler  {
  add                     lsapi:lsphp81 php
}

extprocessor node-backend {
  type                    proxy
  address                 127.0.0.1:3001
  maxConns                100
  pcKeepAliveTimeout      60
  initTimeout             60
  retryTimeout            0
  respBuffer              0
}

context /api/ {
  type                    proxy
  handler                 node-backend
  addDefaultCharset       off
}

context /uploads/ {
  location                \$VH_ROOT/html/uploads/
  allowBrowse             1
  addDefaultCharset       off
}

context / {
  location                \$VH_ROOT/html/dist/
  allowBrowse             1
  indexFiles              index.html
  
  rewrite  {
    enable                1
    inherit               1
    RewriteFile           .htaccess
  }
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
}
$SSL_BLOCK
EOF

echo "✅ Đã ghi đè cấu hình mới."

# RESTART
echo -e "\n${GREEN}[3/3] Khởi động lại OpenLiteSpeed...${NC}"
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart
else
    service lsws restart
fi

echo -e "\n${YELLOW}🔥 XONG! Config đã cập nhật.${NC}"
