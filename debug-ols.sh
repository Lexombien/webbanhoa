#!/bin/bash

# =================================================================
# SCRIPT DEBUG v2: FORCE OVERWRITE CONFIG (FIX ORDER)
# =================================================================

DOMAIN="lemyloi.work.gd"
VHOST_CONF="/usr/local/lsws/conf/vhosts/$DOMAIN/$DOMAIN.conf"

echo "🔧 Đang cấu hình lại (Force Overwrite) cho file: $VHOST_CONF"

# Backup
cp "$VHOST_CONF" "$VHOST_CONF.bak_v2"

# Lấy SSL nếu có
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

# Ghi đè file với thứ tự chuẩn xác
# 1. Extprocessor
# 2. Context /api/ (Quan trọng: phải đứng trước /)
# 3. Context / (Frontend)
# 4. Rewrite rules

cat > "$VHOST_CONF" <<EOF
docRoot                   \$VH_ROOT/html/dist
vhDomain                  $DOMAIN
vhAliases                 www.$DOMAIN
adminEmails               admin@$DOMAIN
enableGzip                1
enableIpGeo               1

index  {
  useServer               0
  indexFiles              index.html
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

$SSL_BLOCK
EOF

# Restart OLS
echo "🔄 Restarting OpenLiteSpeed..."
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart > /dev/null
else
    service lsws restart
fi

echo "✅ Đã ghi đè cấu hình chuẩn. Vui lòng thử lại!"
