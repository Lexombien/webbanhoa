#!/bin/bash

# =================================================================
# SCRIPT DEBUG v3: HTACCESS PROXY METHOD (THE NUCLEAR OPTION)
# =================================================================

DOMAIN="lemyloi.work.gd"
HTML_DIR="/usr/local/lsws/$DOMAIN/html"
DIST_DIR="$HTML_DIR/dist"

echo "🔧 Đang cấu hình .htaccess để Force Proxy API..."

# Đảm bảo thư mục tồn tại
mkdir -p "$DIST_DIR"

# Ghi đè file .htaccess với luật Rewrite Proxy
# Lưu ý: P = Proxy, L = Last Rule
# Chúng ta dùng RewriteRule để đẩy request /api/ sang http://127.0.0.1:3001/api/

cat > "$DIST_DIR/.htaccess" <<EOF
RewriteEngine On
RewriteBase /

# 1. API REQUESTS -> NODEJS BACKEND
# Cú pháp Proxy trong OLS: RewriteRule ^api/(.*)$ http://node-backend/api/\$1 [P,L]
# Nhưng cần định nghĩa 'node-backend' trong config server trước.
# Nếu OLS không hỗ trợ [P] trong .htaccess (bản miễn phí đôi khi hạn chế),
# Ta sẽ quay lại config context nhưng dùng tên KHÁC để tránh conflict.

# Tạm thời dùng lại logic React Router chuẩn, nhưng loại trừ /api/
# Để OLS Server Config xử lý context /api/ (đã config ở bước trước)

# Nếu request là file hoặc folder tồn tại -> phục vụ luôn
RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]

# Nếu request bắt đầu bằng /api/, ĐỪNG áp dụng luật index.html
# Hãy để nó trôi qua (để Context /api/ trong server config xử lý)
RewriteCond %{REQUEST_URI} ^/api/
RewriteRule ^ - [L]

# Các request khác (React Routing) -> index.html
RewriteRule ^ index.html [L]
EOF

echo "✅ Đã cập nhật .htaccess"

# Cập nhật lại server config để chắc chắn context /api/ được ưu tiên
# (Lặp lại logic của version 2 nhưng đảm bảo path đúng)

VHOST_CONF="/usr/local/lsws/conf/vhosts/$DOMAIN/$DOMAIN.conf"
echo "🔧 Re-applying Server Config to: $VHOST_CONF"

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

# ĐỊNH NGHĨA BACKEND
extprocessor node-backend {
  type                    proxy
  address                 127.0.0.1:3001
  maxConns                100
  pcKeepAliveTimeout      60
  initTimeout             60
  retryTimeout            0
  respBuffer              0
}

# CONTEXT API (Phải nằm trên cùng)
context /api/ {
  type                    proxy
  handler                 node-backend
  addDefaultCharset       off
}

# ROOT CONTEXT
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

echo "✅ DONE! Đã cấu hình loại trừ (Exclude) /api/ khỏi React Router."
