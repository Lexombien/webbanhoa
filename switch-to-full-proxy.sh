#!/bin/bash

# =================================================================
# SCRIPT CHUYỂN ĐỔI MÔ HÌNH: FULL PROXY TO NODEJS
# Node.js sẽ gánh cả Web + API. OLS chỉ làm Proxy SSL.
# =================================================================

DOMAIN="lemyloi.work.gd"
VHOST_CONF="/usr/local/lsws/conf/vhosts/$DOMAIN/$DOMAIN.conf"
HTML_DIR="/usr/local/lsws/$DOMAIN/html"

echo "🚀 CHUYỂN ĐỔI SANG CHẾ ĐỘ FULL NODEJS SERVER..."

# 1. Update Server.js và Build lại Frontend
# (Đảm bảo Node.js có code mới nhất để phục vụ Web)
echo "📦 Build lại Frontend..."
cd "$HTML_DIR"

# Nạp NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

git pull
npm install --legacy-peer-deps
chmod -R +x node_modules/.bin/
npm run build

if [ ! -d "dist" ]; then
    echo "❌ Lỗi Build React. Dừng lại."
    exit 1
fi

# 2. Restart Node.js để nhận code mới (đã có static serving)
echo "🔄 Restart Node.js..."
pm2 reload web-backend --update-env || pm2 start server.js --name "web-backend"

# 3. Cấu hình OLS: Chỉ Proxy, không serve file tĩnh
echo "🔧 Cấu hình OLS (Full Proxy Mode)..."

# Backup config cũ
cp "$VHOST_CONF" "$VHOST_CONF.bak_full_proxy"

# Lấy SSL
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

cat > "$VHOST_CONF" <<EOF
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

# FULL PROXY CONTEXT (Chuyển TOÀN BỘ request vào Node)
# Vì Node.js giờ đã biết serve static file và handle API, 
# ta chỉ cần 1 context duy nhất.

context / {
  type                    proxy
  handler                 node-backend
  addDefaultCharset       off
}

$SSL_BLOCK
EOF

# Restart OLS
echo "🔄 Restarting OpenLiteSpeed..."
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart > /dev/null
else
    service lsws restart
fi

echo "✅ CHUYỂN ĐỔI THÀNH CÔNG!"
echo "👉 Node.js hiện đang phụ trách toàn bộ Website."
