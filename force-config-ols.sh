#!/bin/bash

# =================================================================
# OLS AUTO CONFIGURATOR - "MẠNH TAY" (V2 - Smart Search)
# =================================================================

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}   OLS AUTO CONFIG - HARDCORE MODE (V2)            ${NC}"
echo -e "${BLUE}===================================================${NC}"

# 1. TÌM KIẾM FILE CẤU HÌNH
OLS_ROOT="/usr/local/lsws"
CONF_DIR="$OLS_ROOT/conf/vhosts"

echo -e "${YELLOW}[?] Nhập tên miền của bạn (VD: lemyloi.work.gd):${NC}"
read -r DOMAIN_NAME

if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}❌ Lỗi: Chưa nhập tên miền!${NC}"
    exit 1
fi

# Hàm tìm file config
find_config() {
    local TARGET_NAME=$1
    # Check 1: CyberPanel style /conf/vhosts/domain/vhost.conf
    local path1="$CONF_DIR/$TARGET_NAME/vhost.conf"
    # Check 2: Standard OLS style /conf/vhosts/name/vhconf.conf
    local path2="$CONF_DIR/$TARGET_NAME/vhconf.conf"
    
    if [ -f "$path1" ]; then
        echo "$path1"
    elif [ -f "$path2" ]; then
        echo "$path2"
    else
        echo ""
    fi
}

VHOST_CONF=$(find_config "$DOMAIN_NAME")

if [ -z "$VHOST_CONF" ]; then
    echo -e "${RED}❌ Không tìm thấy config cho domain '$DOMAIN_NAME'.${NC}"
    echo -e "\n🔍 Đang liệt kê các Virtual Host hiện có trên VPS:"
    echo "------------------------------------------------"
    ls -1 "$CONF_DIR"
    echo "------------------------------------------------"
    
    echo -e "${YELLOW}[?] Hãy nhập chính xác TÊN THƯ MỤC VHOST (trong danh sách trên) tương ứng với web này:${NC}"
    read -r VHOST_DIR_NAME
    
    if [ -z "$VHOST_DIR_NAME" ]; then
        echo "❌ Đã hủy bỏ."
        exit 1
    fi
    
    VHOST_CONF=$(find_config "$VHOST_DIR_NAME")
    
    if [ -z "$VHOST_CONF" ]; then
        echo -e "${RED}❌ Vẫn không tìm thấy file config (vhost.conf hoặc vhconf.conf) trong $VHOST_DIR_NAME${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Đã tìm thấy file cấu hình: $VHOST_CONF${NC}"

# 2. BACKUP
echo -e "\n${GREEN}[1/3] Backup cấu hình cũ...${NC}"
cp "$VHOST_CONF" "$VHOST_CONF.bak_$(date +%s)"

# 3. TẠO NỘI DUNG CONFIG MỚI
echo -e "\n${GREEN}[2/3] Ghi đè cấu hình...${NC}"

# Xác định đường dẫn SSL tự động
SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"

# Nếu không có SSL LetsEncrypt, thử tìm fallback hoặc để trống
if [ ! -f "$SSL_KEY" ]; then
    echo "⚠️  Không tìm thấy SSL tại đường dẫn Let's Encrypt mặc định."
    # Fallback to self-signed or default if needed, or keep existing paths from backup if we were smarter.
    # For now, warn user.
fi

# GHI ĐÈ FILE CONFIG
# Lưu ý: $VH_ROOT trong OLS tương ứng với thư mục Home của Vhost
# Ví dụ: /usr/local/lsws/lemyloi.work.gd/
# DocRoot nên set là $VH_ROOT/html/dist

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

vhssl  {
  keyFile                 $SSL_KEY
  certFile                $SSL_CERT
  certChain               1
  sslProtocol             24
  enableSpdy              1
  enableQuic              1
}
EOF

echo "✅ Đã ghi cấu hình mới!"

# 4. RESTART OLS
echo -e "\n${GREEN}[3/3] Khởi động lại OpenLiteSpeed...${NC}"
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart
else
    service lsws restart
fi

echo -e "\n${BLUE}===================================================${NC}"
echo -e "${YELLOW}🔥 XONG! Config đã được cập nhật.${NC}"
