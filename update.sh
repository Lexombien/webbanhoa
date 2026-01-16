#!/bin/bash

# =================================================================
# SCRIPT CẬP NHẬT CODE SIÊU TỐC (UPDATE ONLY)
# Phiên bản: Fix triệt để EACCES (esbuild/vite permissions)
# =================================================================

# Màu sắc
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}  🚀 ĐANG CẬP NHẬT WEBSITE... (UPDATE ONLY)       ${NC}"
echo -e "${BLUE}===================================================${NC}"

# 1. Kéo code mới
echo -e "\n${GREEN}[1/4] Git Pull...${NC}"
git pull

# 2. Cài đặt dependencies
echo -e "\n${GREEN}[2/4] Install Dependencies...${NC}"
npm install --legacy-peer-deps

# 🔥 SUPER FIX: CẤP QUYỀN THỰC THI CHO TOÀN BỘ BINARY TRONG NODE_MODULES 🔥
# Đây là giải pháp mạnh tay nhất để sửa lỗi EACCES esbuild/vite
echo -e "\n${GREEN}[Step] Fix quyền thực thi (chmod +x) cho node_modules...${NC}"

# Cách 1: Cấp quyền cho toàn bộ file trong .bin
chmod -R +x node_modules/.bin/

# Cách 2: Tìm và cấp quyền cho esbuild binary (quan trọng nhất)
if [ -d "node_modules/@esbuild" ]; then
    chmod -R +x node_modules/@esbuild
fi

# Cách 3 (Dự phòng): Quét toàn bộ node_modules tìm file thực thi (hơi lâu nhưng chắc ăn)
# find node_modules -type f -name "esbuild" -exec chmod +x {} \;
# find node_modules -type f -name "vite" -exec chmod +x {} \;

# 3. Build React (Thử lại)
echo -e "\n${GREEN}[3/4] Build Frontend (React)...${NC}"
# Đôi khi cần clean cache vite
rm -rf node_modules/.vite
npm run build

# Check xem build có thành công không
if [ $? -eq 0 ]; then
    echo -e "✅ Build thành công."
else
    echo -e "${RED}❌ Lỗi: Build thất bại. Vui lòng cấp quyền thủ công: chmod -R 777 node_modules${NC}"
fi

# 4. Restart Backend
echo -e "\n${GREEN}[4/4] Restart Backend...${NC}"
mkdir -p uploads
chmod -R 777 uploads
pm2 reload web-backend --update-env || pm2 start server.js --name "web-backend"

echo -e "\n${BLUE}===================================================${NC}"
echo -e "   🎉 DONE!${NC}"
echo -e "${BLUE}===================================================${NC}"
