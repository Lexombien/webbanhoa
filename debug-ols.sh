#!/bin/bash

# =================================================================
# SCRIPT DEBUG & FORCE CONFIG OLS (FINAL WEAPON)
# =================================================================

DOMAIN="lemyloi.work.gd"
OLS_ROOT="/usr/local/lsws"

echo "🔍 Đang truy tìm file cấu hình thật sự của $DOMAIN..."

# Tìm tất cả file .conf có chứa tên miền
FOUND_FILES=$(grep -r "$DOMAIN" $OLS_ROOT/conf --include="*.conf" | cut -d: -f1 | sort | uniq)

if [ -z "$FOUND_FILES" ]; then
    echo "❌ Không tìm thấy file config nào chứa $DOMAIN"
    exit 1
fi

echo "✅ Tìm thấy các file sau:"
echo "$FOUND_FILES"

# Hàm inject proxy
inject_proxy() {
    local FILE=$1
    echo "⚡ Đang tiêm cấu hình Proxy vào: $FILE"
    
    # Backup
    cp "$FILE" "$FILE.bak_debug"
    
    # Kiểm tra xem đã có node-backend chưa
    if grep -q "extprocessor node-backend" "$FILE"; then
        echo "   -> File này đã có config node-backend. Bỏ qua."
    else
        # Chèn extprocessor vào đầu context đầu tiên hoặc cuối file
        # Đây là cách chèn an toàn nhất: Thêm vào cuối file nhưng trước dấu đóng } cuối cùng nếu có
        # Hoặc đơn giản là append vào cuối. OLS config khá linh hoạt.
        
        cat >> "$FILE" <<EOF

# --- AUTO INJECTED BY DEBUG SCRIPT ---
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
# -------------------------------------
EOF
        echo "   -> Đã chèn xong."
    fi
}

# Duyệt qua các file tìm được và inject
for FILE in $FOUND_FILES; do
    # Chỉ inject vào file vhost, không inject vào httpd_config.conf chính
    if [[ "$FILE" == *"vhosts"* ]]; then
        inject_proxy "$FILE"
    fi
done

# Restart Backend cho chắc
echo "🔄 Restarting Backend..."
cd $OLS_ROOT/$DOMAIN/html
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
pm2 delete web-backend 2>/dev/null
pm2 start server.js --name "web-backend"

# Restart OLS
echo "🔄 Restarting OpenLiteSpeed..."
if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
    /usr/local/lsws/bin/lswsctrl restart > /dev/null
else
    service lsws restart
fi

echo "✅ DONE! Hãy thử lại."
