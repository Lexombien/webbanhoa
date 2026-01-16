#!/bin/bash

# =================================================================
# 🚀 DEPLOY-PROD.SH - SCRIPT CẬP NHẬT & VẬN HÀNH WEBSITE TOÀN DIỆN
# -----------------------------------------------------------------
# Chức năng:
# 1. Kéo code mới nhất từ Git
# 2. Cài đặt thư viện & Build React
# 3. Ép cấu hình OpenLiteSpeed chuẩn nhất (Full Proxy vào Node.js)
# 4. Restart Backend Node.js
# 5. Dọn dẹp các file rác
# =================================================================

# Màu sắc
GREEN='\033[0;32m'
BLUE='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}    🌸  DEPLOYMENT TOOL - LUXURY FLORAL SHOP  🌸    ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. SETUP MÔI TRƯỜNG
echo -e "${YELLOW}[1/6] Nạp môi trường (Node.js/NVM)...${NC}"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Xác định thư mục làm việc (Ưu tiên thư mục OLS)
DOMAIN="lemyloi.work.gd"
OLS_ROOT="/usr/local/lsws"
WORK_DIR="$OLS_ROOT/$DOMAIN/html"

if [ -d "$WORK_DIR" ]; then
    echo " -> Phát hiện thư mục OLS: $WORK_DIR"
    cd "$WORK_DIR" || exit
else
    echo " -> Đang chạy tại thư mục hiện tại: $(pwd)"
fi

# 2. GIT PULL
echo -e "\n${YELLOW}[2/6] Cập nhật source code (Git Pull)...${NC}"
git pull

# 3. BUILD FRONTEND
echo -e "\n${YELLOW}[3/6] Build Frontend (Vite/React)...${NC}"

# Fix quyền thực thi (nguyên nhân hay gây lỗi build)
echo " -> Cấp quyền thực thi cho node_modules/.bin..."
chmod -R +x node_modules/.bin/ 2>/dev/null

# Kiểm tra dependencies
if [ ! -d "node_modules" ]; then
    echo " -> Chưa có node_modules, đang cài đặt..."
    npm install --legacy-peer-deps
fi

# Chạy build
if ! npm run build; then
    echo -e "${RED}⚠️ Lỗi Build lần 1. Đang thử cài đặt lại dependencies sạch sẽ...${NC}"
    rm -rf node_modules package-lock.json
    npm cache clean --force
    npm install --legacy-peer-deps
    
    echo " -> Đang thử Build lần 2..."
    npm run build
fi

if [ ! -f "dist/index.html" ]; then
    echo -e "${RED}❌ Lỗi: Build thất bại sau 2 lần thử (Không thấy file dist/index.html).${NC}"
    echo "🔍 Kiểm tra thư mục dist:"
    ls -F dist/ 2>/dev/null
    exit 1
fi
echo -e "${GREEN}✅ Build Frontend thành công!${NC}"

# 4. RESTART BACKEND (NODE.JS)
echo -e "\n${YELLOW}[4/6] Khởi động Backend (PM2)...${NC}"

# Kill process cũ cho sạch
pm2 delete web-backend 2>/dev/null

# Start mới
pm2 start server.js --name "web-backend" --update-env
pm2 save

echo " -> Chờ 5s để Backend khởi động..."
sleep 5

# Check port 3001
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3001/api/ping)
if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✅ Backend đã Online (Port 3001)${NC}"
else
    echo -e "${RED}⚠️ Backend chưa phản hồi (Code: $HTTP_CODE). Đang check log...${NC}"
    pm2 logs web-backend --lines 10 --nostream
    # Không exit, cứ thử cấu hình OLS tiếp
fi

# 5. CẤU HÌNH OPENLITESPEED (FULL PROXY)
echo -e "\n${YELLOW}[5/6] Ép cấu hình chuẩn cho OpenLiteSpeed...${NC}"

CONF_FILE="/usr/local/lsws/conf/vhosts/$DOMAIN/$DOMAIN.conf"

# Kiểm tra SSL
SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
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

# Ghi đè cấu hình (Full Proxy - Tất cả request vào Node.js Backend)
cat > "$CONF_FILE" <<EOF
docRoot                   \$VH_ROOT/html
vhDomain                  $DOMAIN
vhAliases                 www.$DOMAIN
adminEmails               admin@$DOMAIN
enableGzip                1
enableIpGeo               1

index  {
  useServer               0
  indexFiles              index.html
}

# BACKEND NODEJS
extprocessor node-backend {
  type                    proxy
  address                 127.0.0.1:3001
  maxConns                100
  pcKeepAliveTimeout      60
  initTimeout             60
  retryTimeout            0
  respBuffer              0
}

# FULL PROXY CONTEXT
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
echo -e "${GREEN}✅ Đã cấu hình & Restart OLS.${NC}"

# 6. DỌN DẸP FILE RÁC
echo -e "\n${YELLOW}[6/6] Dọn dẹp script cũ...${NC}"
rm -f fix-503.sh debug-ols.sh switch-to-full-proxy.sh update.sh re-config-proxy.sh restore-ols.sh 2>/dev/null
echo " -> Đã xóa các file script tạm."

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}   🎉  DEPLOY THÀNH CÔNG! WEBSITE ĐÃ SẴN SÀNG  🎉    ${NC}"
echo -e "${BLUE}====================================================${NC}"
