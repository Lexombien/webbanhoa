#!/bin/bash

# =================================================================
# SCRIPT RE-CONFIG PROXY & CONTEXT (FIX LOGIC API 404/JSON ERROR)
# =================================================================

DOMAIN_NAME="lemyloi.work.gd"
OLS_ROOT="/usr/local/lsws"
CONF_DIR="$OLS_ROOT/conf/vhosts/$DOMAIN_NAME"
VHOST_CONF="$CONF_DIR/vhconf.conf"

# Nếu không tìm thấy vhconf.conf, thử tìm file khác
if [ ! -f "$VHOST_CONF" ]; then
    VHOST_CONF="$CONF_DIR/$DOMAIN_NAME.conf"
fi
if [ ! -f "$VHOST_CONF" ]; then
    VHOST_CONF="$CONF_DIR/vhost.conf"
fi

if [ -z "$VHOST_CONF" ]; then
     echo "❌ Không tìm thấy file config OLS nào cả!"
     exit 1
fi

echo "🔧 Đang cấu hình lại Proxy cho file: $VHOST_CONF"

# Tạo nội dung config mới (Ghi đè phần quan trọng)
# Lưu ý: context /api/ phải nằm TRƯỚC context / để được ưu tiên xử lý
# Dùng Symlink cho uploads nên không cần context uploads nữa (đã xử lý ở ols-install.sh)

# Backup config cũ
cp "$VHOST_CONF" "$VHOST_CONF.bak_proxy_fix"

# Ghi đè cấu hình chuẩn (Giữ lại SSL nếu có - script này ghi đè logic chính)
# Để an toàn, ta chỉ chèn lại đoạn extprocessor và context /api/
# Nhưng vì sed/awk phức tạp, ta ghi đè file với cấu trúc chuẩn.

# Tìm SSL Key cũ để tái sử dụng
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

# 1. Định nghĩa Backend (Node.js chạy ở port 3001)
extprocessor node-backend {
  type                    proxy
  address                 127.0.0.1:3001
  maxConns                100
  pcKeepAliveTimeout      60
  initTimeout             60
  retryTimeout            0
  respBuffer              0
}

# 2. Map /api/ vào Backend (QUAN TRỌNG: Đặt trên cùng)
context /api/ {
  type                    proxy
  handler                 node-backend
  addDefaultCharset       off
}

# 3. Map root / vào thư mục dist (React App)
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

# Restart OLS
echo "🔄 Restarting OpenLiteSpeed..."
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart > /dev/null
else
    service lsws restart
fi

echo "✅ Đã Fix xong Proxy Context! Hãy thử tải lại trang."
