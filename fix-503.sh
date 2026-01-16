#!/bin/bash

# =================================================================
# SCRIPT CỨU HỘ: FIX LỖI 503 SERVICE UNAVAILABLE
# =================================================================

echo -e "\033[0;34m🚑 ĐANG KHẮC PHỤC SỰ CỐ 503...\033[0m"

# 1. Nạp môi trường Node.js
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Di chuyển vào thư mục code
cd /usr/local/lsws/lemyloi.work.gd/html/ || exit

# 2. Kiểm tra xem Frontend đã build chưa
if [ ! -f "dist/index.html" ]; then
    echo -e "\033[0;33m⚠️ Không thấy thư mục dist. Đang build lại Frontend...\033[0m"
    npm install --legacy-peer-deps
    chmod -R +x node_modules/.bin/
    npm run build
fi

# 3. Khởi động lại Backend (Hard Restart)
echo -e "\033[0;32m🔄 Khởi động lại Node.js Backend...\033[0m"
pm2 delete web-backend 2>/dev/null
pm2 start server.js --name "web-backend" --update-env
pm2 save

echo "⏳ Đang chờ Backend khởi động (5s)..."
sleep 5

# 4. Kiểm tra Backend có sống không
echo -e "\033[0;34m🧪 Kiểm tra kết nối Backend...\033[0m"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3001/api/ping)

if [ "$HTTP_CODE" == "200" ]; then
    echo -e "\033[0;32m✅ Backend đã chạy ONLINE (Status 200)\033[0m"
    
    # 5. Restart OLS để nhận kết nối
    echo -e "\033[0;32m🔄 Restart OpenLiteSpeed...\033[0m"
    if [ -f "/usr/local/lsws/bin/lswsctrl" ]; then
        /usr/local/lsws/bin/lswsctrl restart > /dev/null
    else
        service lsws restart
    fi
    
    echo -e "\033[0;32m🎉 ĐÃ SỬA XONG! Website hoạt động trở lại.\033[0m"
else
    echo -e "\033[0;31m❌ Backend vẫn gặp lỗi (Code: $HTTP_CODE). Dưới đây là log lỗi:\033[0m"
    echo "---------------------------------------------------"
    pm2 logs web-backend --lines 30 --nostream
    echo "---------------------------------------------------"
    echo -e "\033[0;33m👉 Hãy chụp ảnh log trên và gửi cho tôi!\033[0m"
fi
