#!/bin/bash

# =================================================================
# OLS ONE-CLICK DEPLOY (FULL PROXY EDITION)
# =================================================================

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}  🚀 OLS INSTALLER - LUXURY FLORAL SHOP  ${NC}"
echo -e "${BLUE}     (NODE.JS FULL PROXY MODE - BEST STABILITY)    ${NC}"
echo -e "${BLUE}===================================================${NC}"

# Check Root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Lỗi: Vui lòng chạy script bằng quyền root (sudo).${NC}"
    exit 1
fi

# 1. NHẬP THÔNG TIN
echo -e "${YELLOW}[1/3] Nhập tên miền (VD: lemyloi.work.gd):${NC}"
read -r DOMAIN_NAME

while [ -z "$DOMAIN_NAME" ]; do
    read -p "❌ Không được để trống. Nhập lại: " DOMAIN_NAME
done

# 2. NHẬP MẬT KHẨU ADMIN (CHO .ENV)
echo -e "\n${YELLOW}[2/3] Nhập Mật khẩu quản trị Admin (Mặc định: admin123):${NC}"
read -s ADMIN_PASS
if [ -z "$ADMIN_PASS" ]; then
    ADMIN_PASS="admin123"
fi
echo -e "✅ Đã lưu mật khẩu."

RAND_PASS=$ADMIN_PASS # Gán biến để dùng ở bước sau

# Xác định thư mục
OLS_ROOT="/usr/local/lsws"
WORK_DIR="$OLS_ROOT/$DOMAIN_NAME/html"

echo -e "\n${YELLOW}[3/3] Chuẩn bị cài đặt vào: $WORK_DIR${NC}"
echo "Bấm Enter để tiếp tục..."
read -r

# 3. SETUP MÔI TRƯỜNG NODE.JS
echo -e "\n${BLUE}➤ Cài đặt Node.js & PM2...${NC}"
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

# 4. SETUP SOURCE CODE
mkdir -p "$WORK_DIR"
cp -r . "$WORK_DIR/" 2>/dev/null || echo "Copying files..."
cd "$WORK_DIR" || exit

# 5. TẠO FILE .ENV (BẢO MẬT)
echo -e "\n${BLUE}➤ Tạo file cấu hình bảo mật (.env)...${NC}"
if [ ! -f ".env" ]; then
    cat > .env <<EOF
PORT=3001
HOST=0.0.0.0
ADMIN_USERNAME=admin
ADMIN_PASSWORD=$RAND_PASS
EOF
    echo "✅ Đã tạo .env mới."
else
    echo "ℹ️  File .env đã tồn tại, giữ nguyên."
    # Lấy pass cũ để hiển thị cuối cùng
    EXISTING_PASS=$(grep ADMIN_PASSWORD .env | cut -d '=' -f2)
    if [ ! -z "$EXISTING_PASS" ]; then RAND_PASS=$EXISTING_PASS; fi
fi

# 6. BUILD PROJECT
echo -e "\n${BLUE}➤ Cài đặt & Build Project...${NC}"
chmod -R +x node_modules/.bin/ 2>/dev/null
if [ ! -d "node_modules" ]; then
    npm install --legacy-peer-deps
fi
npm run build

# 7. START BACKEND
echo -e "\n${BLUE}➤ Khởi động Backend Code...${NC}"
pm2 delete web-backend 2>/dev/null
pm2 start server.js --name "web-backend" --update-env
pm2 save

# 8. CONFIG OPENLITESPEED (FULL PROXY MODE)
echo -e "\n${BLUE}➤ Áp cấu hình OLS (Full Proxy)...${NC}"
CONF_FILE="/usr/local/lsws/conf/vhosts/$DOMAIN_NAME/$DOMAIN_NAME.conf"

# Kiểm tra SSL có sẵn không
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
fi

# Ghi cấu hình Proxy 100% vào file
cat > "$CONF_FILE" <<EOF
docRoot                   \$VH_ROOT/html
vhDomain                  $DOMAIN_NAME
vhAliases                 www.$DOMAIN_NAME
adminEmails               admin@$DOMAIN_NAME
enableGzip                1
enableIpGeo               1

index  {
  useServer               0
  indexFiles              index.html
}

# BACKEND NODEJS EXTPROCESSOR
extprocessor node-backend {
  type                    proxy
  address                 127.0.0.1:3001
  maxConns                100
  pcKeepAliveTimeout      60
  initTimeout             60
  retryTimeout            0
  respBuffer              0
}

# FULL SITE PROXY CONTEXT
context / {
  type                    proxy
  handler                 node-backend
  addDefaultCharset       off
}

$SSL_BLOCK
EOF

# Restart OLS
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart > /dev/null
else
    service lsws restart
fi

# 9. HOÀN TẤT
echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}🎉 CÀI ĐẶT THÀNH CÔNG! HỆ THỐNG ĐÃ ONLINE.${NC}"
echo -e "${GREEN}=================================================${NC}"
echo -e "👉 Website:   http://$DOMAIN_NAME"
echo -e "👉 Admin Url: http://$DOMAIN_NAME/admin"
echo -e "🔑 Tài khoản: admin"
echo -e "🔑 Mật khẩu:  $RAND_PASS"
echo -e "${YELLOW}(Hãy lưu lại mật khẩu này ngay!)${NC}"
echo -e "================================================="
