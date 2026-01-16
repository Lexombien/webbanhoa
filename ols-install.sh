#!/bin/bash

# =================================================================
# OLS ONE-CLICK DEPLOY SCRIPT (OPENLITESPEED SPECIAL EDITION)
# VERSION: SYMLINK FIX (BEST FOR IMAGES)
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
echo -e "${BLUE}     Phiên bản FIX ẢNH BẰNG SYMLINK (TRIỆT ĐỂ)    ${NC}"
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

# Hàm ghi config CONFIG (ĐƠN GIẢN HÓA VÌ ĐÃ DÙNG SYMLINK)
write_ols_config() {
    local SSL_BLOCK_CONTENT=$1
    
    # Ở đây KHÔNG CẦN Context /uploads/ nữa vì Symlink đã xử lý rồi
    # OLS sẽ tự hiểu /uploads/ là file nằm trong dist/uploads (vốn là link)
    
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

# =================================================================
# 2. CÀI ĐẶT & BUILD
# =================================================================
# Load NVM & Install Node (Skipped specific check details for brevity)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! command -v node &> /dev/null; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm use 20
fi

if ! command -v pm2 &> /dev/null; then
    npm install -g pm2
    pm2 startup
fi

# Tạo .env
cat > .env <<EOF
PORT=3001
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
BOT_TOKEN=
OWNER_ZALO_IDS=
WEBHOOK_SECRET=tientienflorist-secret-2026
SHOP_NAME=Tientienflorist
EOF

# Build
if [ -d "node_modules" ]; then rm -rf node_modules; fi
npm install --legacy-peer-deps
npm run build
mkdir -p uploads

# =================================================================
# 🔥 QUAN TRỌNG: TẠO SYMLINK CHO UPLOADS
# =================================================================
echo -e "\n${GREEN}[Step] Tạo Symlink cho thư mục Uploads...${NC}"
# Đảm bảo folder gốc tồn tại & có quyền 777
chmod -R 777 "$CURRENT_DIR/uploads"

# Vào dist, xóa uploads ảo và link tới uploads thật
cd "$CURRENT_DIR/dist"
rm -rf uploads
ln -s ../uploads uploads
echo "✅ Đã tạo Symlink: dist/uploads -> ../uploads"

# Quay lại root
cd "$CURRENT_DIR"

# Start Backend
if pm2 list | grep -q "web-backend"; then
    pm2 reload web-backend --update-env
else
    pm2 start server.js --name "web-backend"
    pm2 save
fi


# =================================================================
# 3. CONFIG OLS
# =================================================================
echo -e "\n${GREEN}[5/5] Cấu hình OpenLiteSpeed...${NC}"

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

# SSL Setup & Config Write (Simplified)
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
    if [ "$SETUP_SSL" == "y" ]; then
         certbot certonly --webroot -w "$CURRENT_DIR/dist" -d "$DOMAIN_NAME" --agree-tos --email "admin@$DOMAIN_NAME" --non-interactive --force-renewal
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

# Config .htaccess for React
cat > "$CURRENT_DIR/dist/.htaccess" <<EOF
RewriteEngine On
RewriteBase /
RewriteRule ^index\.html$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.html [L]
EOF

# Write main OLS config (No need for uploads context anymore due to Symlink)
write_ols_config "$SSL_BLOCK"

echo -e "\n${GREEN}[Step] Restart OLS...${NC}"
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart > /dev/null
else
    service lsws restart
fi

echo -e "\n${BLUE}===================================================${NC}"
echo -e "   🎉 TRIỂN KHAI THÀNH CÔNG (FULL FIX)!${NC}"
echo -e "${BLUE}===================================================${NC}"
