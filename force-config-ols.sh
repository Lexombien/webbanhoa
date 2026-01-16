#!/bin/bash

# =================================================================
# OLS AUTO CONFIGURATOR - "MẠNH TAY"
# Can thiệp trực tiếp vào file XML Configuration của OpenLiteSpeed
# =================================================================

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}   OLS AUTO CONFIG - HARDCORE MODE                 ${NC}"
echo -e "${BLUE}===================================================${NC}"

# 1. TÌM KIẾM FILE CẤU HÌNH
# Giả định đường dẫn CyberPanel/OLS chuẩn
OLS_ROOT="/usr/local/lsws"
CONF_DIR="$OLS_ROOT/conf/vhosts"

echo -e "${YELLOW}[?] Nhập tên miền của bạn (VD: lemyloi.work.gd):${NC}"
read -r DOMAIN_NAME

if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}❌ Lỗi: Chưa nhập tên miền!${NC}"
    exit 1
fi

# Tìm file config vhost
# CyberPanel thường lưu ở: /usr/local/lsws/conf/vhosts/<domain>/vhost.conf (hoặc tương tự)
VHOST_CONF="$CONF_DIR/$DOMAIN_NAME/vhost.conf"

if [ ! -f "$VHOST_CONF" ]; then
    echo -e "${RED}❌ Không tìm thấy file config tại: $VHOST_CONF${NC}"
    echo "Đang thử tìm kiếm..."
    FOUND_PATH=$(find $OLS_ROOT -name "vhost.conf" | grep "$DOMAIN_NAME" | head -n 1)
    
    if [ -z "$FOUND_PATH" ]; then
        echo -e "${RED}❌ Hoàn toàn không tìm thấy config cho domain này. Bạn đã tạo Website trong CyberPanel/OLS chưa?${NC}"
        exit 1
    else
        VHOST_CONF="$FOUND_PATH"
        echo -e "${GREEN}✅ Đã tìm thấy: $VHOST_CONF${NC}"
    fi
fi

# 2. BACKUP
echo -e "\n${GREEN}[1/3] Backup cấu hình cũ...${NC}"
cp "$VHOST_CONF" "$VHOST_CONF.bak_$(date +%s)"
echo "✅ Đã backup thành công."

# 3. TẠO NỘI DUNG CONFIG MỚI
# Chúng ta sẽ giữ lại các phần cơ bản nhưng ghi đè phần Context và Root
# Lưu ý: Đây là template chuẩn cho dự án React + Node.js trên OLS

echo -e "\n${GREEN}[2/3] Ghi đè cấu hình chuẩn...${NC}"

# Đường dẫn tuyệt đối
DOC_ROOT="$OLS_ROOT/$DOMAIN_NAME/html/dist"
UPLOADS_DIR="$OLS_ROOT/$DOMAIN_NAME/html/uploads"

# Nội dung config mới
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

errorlog $OLS_ROOT/logs/$DOMAIN_NAME.error_log {
  useServer               0
  logLevel                ERROR
  rollingSize             10M
}

accesslog $OLS_ROOT/logs/$DOMAIN_NAME.access_log {
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
  rewrite  {
  }
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
  keyFile                 /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem
  certFile                /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem
  certChain               1
  sslProtocol             24
  enableSpdy              1
  enableQuic              1
}
EOF

echo "✅ Đã ghi cấu hình mới bao gồm:"
echo "   - Document Root -> dist"
echo "   - Proxy /api/ -> 127.0.0.1:3001"
echo "   - Uploads folder map -> html/uploads"
echo "   - SSL Paths (Let's Encrypt)"

# 4. RESTART OLS
echo -e "\n${GREEN}[3/3] Khởi động lại OpenLiteSpeed...${NC}"

# Thử restart bằng lệnh lsws
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart
    echo "✅ OLS Restarted via lswsctrl"
else
    # Thử restart service
    service lsws restart
    echo "✅ OLS Restarted via Service"
fi

echo -e "\n${BLUE}===================================================${NC}"
echo -e "${YELLOW}🔥 XONG! HÃY THỬ TRUY CẬP WEBSITE NGAY.${NC}"
echo -e "${BLUE}===================================================${NC}"
