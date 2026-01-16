#!/bin/bash

# =================================================================
# OLS ONE-CLICK DEPLOY SCRIPT (OPENLITESPEED SPECIAL EDITION)
# VERSION: FIX UPLOADS CONTEXT PATH ($VH_ROOT issue)
# =================================================================

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}  🚀 OLS ONE-CLICK DEPLOY (For Tientien Florist)  ${NC}"
echo -e "${BLUE}     Phiên bản FIX LỖI ẢNH (UPLOADS)               ${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""

# Check Root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Lỗi: Vui lòng chạy script bằng quyền root (sudo).${NC}"
    exit 1
fi

# =================================================================
# 1. THU THẬP THÔNG TIN
# =================================================================
echo -e "${YELLOW}[1/4] Nhập tên miền (VD: lemyloi.work.gd):${NC}"
read -r DOMAIN_NAME

while [ -z "$DOMAIN_NAME" ]; do
    read -p "❌ Không được để trống. Nhập lại: " DOMAIN_NAME
done

echo -e "\n${YELLOW}[2/4] Nhập TÊN TÀI KHOẢN ADMIN (Mặc định: admin):${NC}"
read -r ADMIN_USER
if [ -z "$ADMIN_USER" ]; then
    ADMIN_USER="admin"
fi

echo -e "\n${YELLOW}[3/4] Nhập MẬT KHẨU ADMIN:${NC}"
read -s ADMIN_PASS
echo -e "✅ Mật khẩu đã lưu."

echo -e "\n${YELLOW}[4/4] Bạn có muốn cài SSL (HTTPS) không? (y/n):${NC}"
read -r SETUP_SSL

# Xác nhận thư mục
CURRENT_DIR=$(pwd)
echo -e "\n${BLUE}ℹ️  Thư mục hiện tại: ${YELLOW}$CURRENT_DIR${NC}"
echo "Bấm Enter để BẮT ĐẦU CÀI ĐẶT..."
read -r

# Hàm ghi config (SỬA LỖI ĐƯỜNG DẪN TẠI ĐÂY)
write_ols_config() {
    local SSL_BLOCK_CONTENT=$1
    # QUAN TRỌNG: Dùng đường dẫn tuyệt đối cho uploads location
    # Thay vì $VH_ROOT, ta dùng thẳng /usr/local/lsws/$DOMAIN_NAME/html/uploads/
    # Vì $VH_ROOT đôi khi bị hiểu sai trong context con.
    
    local ABS_UPLOADS_PATH="/usr/local/lsws/$DOMAIN_NAME/html/uploads/"
    
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
  location                $ABS_UPLOADS_PATH
  allowBrowse             1
  addDefaultCharset       off
  rewrite  {
  }
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
$SSL_BLOCK_CONTENT
EOF
}

# 2. CÀI ĐẶT NODE & CODE (TÓM TẮT)
# ... (Phần này giữ nguyên hoặc chạy nhanh nếu đã cài rồi)

# Tìm file config OLS
OLS_ROOT="/usr/local/lsws"
CONF_DIR="$OLS_ROOT/conf/vhosts"
VHOST_CONF=""

# Smart Find Config
if [ -f "$CONF_DIR/$DOMAIN_NAME/vhconf.conf" ]; then
    VHOST_CONF="$CONF_DIR/$DOMAIN_NAME/vhconf.conf"
elif [ -f "$CONF_DIR/$DOMAIN_NAME/vhost.conf" ]; then
    VHOST_CONF="$CONF_DIR/$DOMAIN_NAME/vhost.conf"
elif [ -f "$CONF_DIR/$DOMAIN_NAME/$DOMAIN_NAME.conf" ]; then
    VHOST_CONF="$CONF_DIR/$DOMAIN_NAME/$DOMAIN_NAME.conf"
fi

if [ -z "$VHOST_CONF" ]; then
    echo -e "${RED}❌ Không tìm thấy file config OLS!${NC}"
    exit 1
fi

echo -e "\n${GREEN}[Step] Cấu hình OpenLiteSpeed (Fix Context Uploads)...${NC}"
echo "File Config: $VHOST_CONF"

# Kiểm tra SSL Key có sẵn không để tái sử dụng
SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
SSL_BLOCK=""

if [ -f "$SSL_KEY" ]; then
    echo "✅ Phát hiện SSL đã cài đặt, sẽ giữ nguyên."
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
    if [ "$SETUP_SSL" == "y" ]; then
        # ...Logic cài SSL (Giống phiên bản trước)...
        echo "Cài SSL..."
        certbot certonly --webroot -w "$CURRENT_DIR/dist" -d "$DOMAIN_NAME" --agree-tos --email "admin@$DOMAIN_NAME" --non-interactive --force-renewal
        # Update SSL Paths
        SSL_BLOCK="
vhssl  {
  keyFile                 $SSL_KEY
  certFile                $SSL_CERT
  certChain               1
  sslProtocol             24
  enableSpdy              1
  enableQuic              1
}"
    fi
fi

# Ghi config
write_ols_config "$SSL_BLOCK"

echo -e "\n${GREEN}[Step] Cấp quyền thư mục Uploads (777)...${NC}"
# Đảm bảo OLS đọc được file
chmod -R 777 /usr/local/lsws/$DOMAIN_NAME/html/uploads/
# Hoặc nếu path khác
chmod -R 777 "$CURRENT_DIR/uploads/"

echo -e "\n${GREEN}[Step] Restart OLS...${NC}"
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart > /dev/null
else
    service lsws restart
fi

echo -e "\n${BLUE}===================================================${NC}"
echo -e "   🎉 ĐÃ FIX XONG LỖI ẢNH!${NC}"
echo -e "   Hãy tải lại trang web và kiểm tra."
echo -e "${BLUE}===================================================${NC}"
